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
            minput <- getInputLine ""
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
  let state = initialState directory
  forM [1..5] (\i -> forkIO $ runPaxos directory i "hi")
  runConsole

runPaxos :: Directory -> Int -> String -> IO ()
runPaxos dir pid entry = do
  let state = initialState dir pid
  sp <- execStateT propose state
  loop sp state
  where
    loop ps as = do
      msg <- receive (plookup dir pid)
      ps' <- execStateT (proposer entry msg) ps
      as' <- execStateT (acceptor msg) as
      loop ps' as'
