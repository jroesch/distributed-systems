module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Concurrent
import Control.Monad.State
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
-- Paxos Imports
import System.Console.Haskeline
import Paxos
import Paxos.Message
import Paxos.Directory

import System.Log.Logger
import System.Log.Handler.Simple


runConsole :: IO ()
runConsole = runInputT defaultSettings loop
    where loop = do
            minput <- getInputLine "> "
            case minput of
              Nothing     -> return ()
              Just "exit" -> return ()
              Just input  -> do
                outputStrLn $ "Echo: " ++ input
                loop

setupLogging :: IO a -> IO ()
setupLogging action = do
  fh <- fileHandler "log/paxos.log" DEBUG
  updateGlobalLogger rootLoggerName (addHandler fh)
  updateGlobalLogger "paxos" (setLevel DEBUG)
  debugM "paxos" "Starting up application..."
  action
  debugM "paxos" "Shutting down application..."

main :: IO ()
main = setupLogging $ do
  directory <- mkDirectory [1..5]
  let state = initialState directory 1
  forM [1..4] (forkIO . runAcceptor state)
  _ <- forkFinally (runProposer (state) 1 "hi") $ \c -> case c of
          Left  e -> error $ show e
          Right _ -> error "Done"
  runConsole

execPaxos :: PaxosState -> PaxosInstance a -> IO ()
execPaxos st p = execStateT p st >> return ()

runAcceptor :: PaxosState -> Int -> IO ()
runAcceptor st pid = do
  forever $ execPaxos st $ do
    s <- get
    msg <- lift $ receive (plookup (dir s) pid)
    acceptor msg
  return ()

runProposer :: PaxosState -> Int -> String -> IO ()
runProposer st pid entry = stRun >> return ()
  where stRun = execPaxos st $ do
          propose
          forever $ do
            s <- get
            msg <- lift $ receive (plookup (dir s) pid)
            proposer entry msg
