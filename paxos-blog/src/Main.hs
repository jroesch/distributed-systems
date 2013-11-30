module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Concurrent
import Control.Monad.State
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
import Data.Sequence
-- Paxos Imports
import System.Console.Haskeline
import Paxos
import Paxos.Message
import Paxos.Directory
import Paxos.Remote

import System.Log.Logger
import System.Log.Handler.Simple


runConsole :: Chan Message -> MVar (Seq Entry) -> MVar Int -> Directory -> Int -> IO ()
runConsole chan var instVar dir pid = runInputT defaultSettings loop
    where loop = do
            minput <- getInputLine "> "
            case minput of
              Nothing     -> return ()
              Just "exit" -> return ()
              Just input  -> do
                case input of
                  'p':'o':'s':'t':' ':rest -> do
                    c <- lift $ dupChan chan
                    lift $ forkIO $ proposeValue c instVar dir pid rest
                    return ()
                  "read" -> lift $ readMVar var >>= print
                  "fail" -> return ()
                  "unfail" -> return ()
                loop

setupLogging :: IO a -> IO ()
setupLogging action = do
  fh <- fileHandler "log/paxos.log" DEBUG
  updateGlobalLogger rootLoggerName (addHandler fh)
  updateGlobalLogger "paxos" (setLevel ERROR)
  debugM "paxos" "Starting up application..."
  action
  debugM "paxos" "Shutting down application..."

main :: IO ()
main = setupLogging $ do
  directory <- mkDirectory [1..5]
  let state = initialState directory
  list <- newMVar empty
  inst <- newMVar 0
  chans <- forM [1..5] (\i -> runPaxos directory i list)
  runConsole (chans !! 1) list inst directory 1

getInst :: MVar Int -> IO Int
getInst mvar = modifyMVar mvar (\v -> return (v + 1, v))

proposeValue :: Chan Message -> MVar Int -> Directory -> Int -> String -> IO ()
proposeValue chan instVar dir pid entry = do
  inst <- getInst instVar
  evalStateT (do
    propose
    loop inst
    ) $ initialState dir pid inst -- TODO: select correct instance
  return ()
  where
    loop inst = do
      Message i msg <- lift $ readChan chan
      -- only read our instance methods
      if i == inst then do
        proposer entry msg
        loop inst
      else loop inst

runPaxos :: Directory -> Int -> MVar (Seq Entry) -> IO (Chan Message)
runPaxos dir pid mvar = do
  c <- newChan -- all messages will be sent through this channel
  forkIO $ forever $ do
    msg <- receive (plookup dir pid)
    writeChan c msg
  forkIO $ runAcceptors c dir pid mvar
  return c

runAcceptors :: Chan Message -> Directory -> Int -> MVar (Seq Entry) -> IO ()
runAcceptors chan dir pid mvar = do
  loop $ [initialState dir pid i | i <- [0..]]
  where
    loop a = do
      Message i msg <- readChan chan
      let inst = a !! i
      (o, s) <- runStateT (acceptor msg) $ a !! i
      case o of
        Just v -> do
          if pid == 1 then
            modifyMVar_ mvar (\var -> return $ var |> v)
          else return ()
        Nothing -> return ()
      loop $ replaceAtIndex i s a
    replaceAtIndex n item ls = a ++ (item:b) where (a, (_:b)) = Prelude.splitAt n ls

