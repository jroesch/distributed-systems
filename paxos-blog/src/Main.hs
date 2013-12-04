module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Concurrent
import Control.Monad.State
import Control.Monad
import Control.Concurrent.Chan
import Control.Concurrent.Timer
import Control.Concurrent.Suspend.Lifted (msDelay)
import qualified Data.Map as M
import Data.Sequence
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

runConsole :: Chan Entry -> MVar (Seq Entry) -> MVar Int -> MVar Bool -> Directory -> Int -> IO ()
runConsole chan var instVar fail dir pid = runInputT defaultSettings loop
    where loop = do
            minput <- getInputLine "> "
            case minput of
              Nothing     -> return ()
              Just "exit" -> return ()
              Just input  -> do
                case input of
                  'p':'o':'s':'t':' ':rest -> lift $ writeChan chan rest
                  "read" -> lift $ readMVar var >>= print
                  "fail" -> lift $ modifyMVar_ fail (\_ -> return True)
                  "unfail" -> lift $ modifyMVar_ fail (\_ -> return False)
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
    proposeValue pChan inst directory pid r
  runConsole proposeChan list inst fail directory pid

getInst :: MVar Int -> IO Int
getInst mvar = modifyMVar mvar (\v -> return (v + 1, v))

-- Propose a value to paxos
proposeValue :: Chan Message -> MVar Int -> Directory -> Int -> String -> IO ()
proposeValue chan instVar dir pid entry = do
  inst <- getInst instVar
  st <- initialState dir pid inst instVar
  execStateT propose st -- initial proposal TODO: is this needed?
  timer <- repeatedTimer (execStateT propose st >> return ()) $ msDelay 2000000 -- TODO: configurable
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
            lift $ debugM "paxos.propose" $ "Proposal in instance " ++ show inst ++ " failed"
            lift $ stopTimer timer
            lift $ proposeValue chan instVar dir pid entry
          Nothing -> loop inst timer
      else loop inst timer

runPaxos :: Directory -> Int -> MVar Int -> MVar (Seq Entry) -> MVar Bool -> IO (Chan Message)
runPaxos dir pid instVar mvar fail = do
  c <- newChan -- all messages will be sent through this channel
  forkIO $ forever $ do
    msg <- receive dir
    b <- readMVar fail
    case b of
      False -> writeChan c msg
      True -> return ()
  forkIO $ runAcceptors c instVar dir pid mvar
  return c

runAcceptors :: Chan Message -> MVar Int -> Directory -> Int -> MVar (Seq Entry) -> IO ()
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
        Just v -> do
          -- decided on value
          modifyMVar_ mvar (\var -> return $ var |> v)
        Nothing -> return ()
      loop $ replaceAtIndex i (Right s) a
    replaceAtIndex n item ls = a ++ (item:b) where (a, (_:b)) = Prelude.splitAt n ls

