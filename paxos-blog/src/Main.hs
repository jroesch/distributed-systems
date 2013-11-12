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
import Paxos.Directory

import System.Log.Logger
import System.Log.Handler.Simple

-- main = runInputT defaultSettings loop
--   where loop = do
--           minput <- getInputLine "> "
--           case minput of
--             Nothing     -> return ()
--             Just "exit" -> return ()
--             Just input   -> do
--               outputStrLn $ "Echo: " ++ input
--               loop

main = do
  fh <- fileHandler "log/paxos.log" DEBUG
  updateGlobalLogger rootLoggerName (addHandler fh)
  dir <- mkDirectory [1..5]
  forM [1..4] (forkIO . runAcceptor dir)
  runProposer dir 1 "hi"

runAcceptor :: Directory -> Int -> IO ()
runAcceptor dir pid = do
  let state = initialState dir pid
  execStateT (forever $ do
    msg <- lift $ receive (plookup dir pid)
    acceptor msg)
    state
  return ()

runProposer :: Directory -> Int -> String -> IO ()
runProposer dir pid entry = do
    let state = initialState dir pid
    execStateT (do
      propose
      forever $ do
        msg <- lift $ receive (plookup dir pid)
        proposer entry msg
      )
      state
    return ()
