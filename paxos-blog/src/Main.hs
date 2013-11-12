module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
-- Paxos Imports
import System.Console.Haskeline
import Paxos
import Paxos.Directory

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
  dir <- mkDirectory [1..5]
  forM [1..4] (forkIO . runAcceptor dir)
  forkIO $ runProposer dir 1 "hi"

runAcceptor :: Directory -> Int -> IO ()
runAcceptor dir pid = do
  state <- initialState pid
  execStateT (forever $ do
    msg <- receive (pLookup dir pid)
    acceptor msg)
    state

runProposer :: Directory -> Int -> String -> IO ()
runProposer dir pid entry = do
    state <- initialState pid
    execStateT (do
      propose
      forever $ do
        msg <- receive (pLookup dir pid)
        proposer entry msg
      )
      state
