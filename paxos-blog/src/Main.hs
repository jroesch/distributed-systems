module Main where

import Prelude as P hiding (replicate)
import Data.Functor ((<$>))
import Data.Maybe
import Control.Concurrent
import Control.Monad.State
import Control.Monad
import Control.Concurrent.Chan
import Control.Concurrent.Timer
import Control.Concurrent.Suspend.Lifted (msDelay)
import qualified Data.Map as M
import Data.Vector as V
-- Paxos Imports
import System.Console.Haskeline
import Paxos
import Paxos.Message
import Paxos.Directory.Remote
import Paxos.Remote

import System.Log.Logger
import System.Log.Handler.Simple
import System.Environment
import System.IO

runConsole :: Chan Entry -> MVar (Vector Value) -> MVar Int -> MVar Bool -> Directory -> Int -> IO ()
runConsole chan var instVar fail dir pid = runInputT defaultSettings loop
    where loop = do
            minput <- getInputLine "> "
            case minput of
              Nothing     -> return ()
              Just "exit" -> return ()
              Just input  -> do
                case input of
                  'p':'o':'s':'t':'(':rest -> lift $ writeChan chan $ P.init rest
                  "read()" -> lift $ readMVar var >>= print . catMaybes . toList
                  "fail()" -> lift $ modifyMVar_ fail (\_ -> return True)
                  "unfail()" -> do
                    lift $ modifyMVar_ fail (\_ -> return False)
                    -- TODO: unfail last
                    i <- lift $ readMVar instVar
                    lift $ broadcast dir $ Learn pid i
                  _ -> lift $ putStrLn "invalid command"
                loop

setupLogging :: IO a -> IO ()
setupLogging action = do
  fh <- fileHandler "log/paxos.log" DEBUG
  updateGlobalLogger rootLoggerName (addHandler fh)
  updateGlobalLogger "paxos" (setLevel DEBUG)
  debugM "paxos" "Starting up application..."
  action
  debugM "paxos" "Shutting down application..."

configFromFile :: IO [(Int, String, Int)]
configFromFile = do
    contents <- readFile "paxos.config"
    return $ read contents

main :: IO ()
main = setupLogging $ do
  putStrLn "Version 1"
  args <- getArgs
  let port = (read $ args !! 0 :: Int)
      pid  = (read $ args !! 1 :: Int)
  config <- configFromFile
  directory <- mkDirectory port pid config
  let state = initialState directory
  proposeChan <- newChan
  list <- newMVar empty
  inst <- newMVar 0
  fail <- newMVar False
  chan <- runPaxos directory pid inst list fail
  pChan <- dupChan chan -- chan for proposer to read from
  forkIO $ forever $ do -- try to propose new values
    r <- readChan proposeChan
    forkIO $ proposeValue pChan inst directory pid r -- remove forkio for no optimization
  runConsole proposeChan list inst fail directory pid

getInst :: MVar Int -> IO Int
getInst mvar = modifyMVar mvar (\v -> return (v + 1, v))

-- Propose a value to paxos
proposeValue :: Chan Message -> MVar Int -> Directory -> Int -> String -> IO ()
proposeValue chan instVar dir pid entry = do
  inst <- getInst instVar
  st <- initialState dir pid inst instVar
  execStateT propose st -- initial proposal TODO: is this needed?
  timer <- repeatedTimer (execStateT propose st >> return ()) $ msDelay 5000 -- TODO: configurable
  evalStateT (loop inst timer) st
  return ()
  where
    loop inst timer = do
      Message i msg <- lift $ readChan chan
      -- only read our instance methods
      if i == inst then do
        res <- proposer entry msg -- TODO: need to update inst if we fail
        case res of
          Just True -> lift $ stopTimer timer -- Successfully proposed
          Just False -> do -- someone else sucessfully proposed, TODO: try another instance?
            lift $ modifyMVar_ instVar $ \oldInst -> return $ max oldInst (inst + 1)
            lift $ debugM "paxos.propose" $ "Proposal in instance " P.++ show inst P.++ " failed"
            lift $ stopTimer timer
            lift $ putStrLn $ "Failed to write " P.++ entry
            -- lift $ proposeValue chan instVar dir pid entry
          Nothing -> loop inst timer
      else loop inst timer

runPaxos :: Directory -> Int -> MVar Int -> MVar (Vector Value) -> MVar Bool -> IO (Chan Message)
runPaxos dir pid instVar mvar fail = do
  c <- newChan -- all messages will be sent through this channel
  forkIO $ forever $ do
    msg <- receive dir
    case msg of
      Learn oPid i -> if oPid /= pid then do
          vec <- readMVar mvar
          send dir oPid $ Have i (V.drop i vec)
        else
          return ()
      Have i v -> do
        modifyMVar_ mvar $ \vec -> do
          let diff = V.length v + i - V.length vec
          let vvec = if diff > 0 then vec V.++ (V.replicate diff Nothing) else vec
          let out = vvec `update` V.filter (isJust . snd) (V.map (\(a, b) -> (a+i,b)) $ indexed v)
          modifyMVar_ instVar (\inst -> return $ max inst (V.length out))
          return out
      _ -> do
        b <- readMVar fail
        case b of
          False -> writeChan c msg
          True -> return ()
  forkIO $ runAcceptors c instVar dir pid mvar
  return c

runAcceptors :: Chan Message -> MVar Int -> Directory -> Int -> MVar (Vector Value) -> IO ()
runAcceptors chan instVar dir pid mvar = do
  loop $ [Left i | i <- [0..]]
  where
    loop a = do
      Message i msg <- readChan chan
      let oInst = a !! i
      inst <- case oInst of
        Left ind -> initialState dir pid ind instVar
        Right st -> return st
      (o, s) <- runStateT (acceptor msg) inst
      case o of
        Just v -> modifyMVar_ mvar (\var -> do -- decided on value
            let diff = i - V.length var
            let vec = if diff >= 0 then var V.++ (replicate (diff + 1) Nothing) else var
            return $ vec // [(i, Just v)])
        Nothing -> return ()
      loop $ replaceAtIndex i (Right s) a
    replaceAtIndex n item ls = a P.++ (item:b) where (a, (_:b)) = P.splitAt n ls

