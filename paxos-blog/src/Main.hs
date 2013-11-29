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
  updateGlobalLogger "paxos" (setLevel ERROR)
  debugM "paxos" "Starting up application..."
  action
  debugM "paxos" "Shutting down application..."

main :: IO ()
main = setupLogging $ do
  directory <- mkDirectory [1..5]
  let state = initialState directory
  list <- newMVar empty
  chans <- forM [1..5] (\i -> runPaxos directory i list)
  c <- dupChan $ chans !! 1
  proposeValue c directory 1 "hi"
  runConsole

proposeValue :: Chan Message -> Directory -> Int -> String -> IO ()
proposeValue chan dir pid entry = do
  evalStateT (do
    propose
    loop
    ) $ initialState dir pid 0 -- TODO: select correct instance
  return ()
  where
    loop = do
      Message i msg <- lift $ readChan chan
      if i == 0 then do
        proposer entry msg
        loop
      else loop

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
          modifyMVar_ mvar (\var -> return $ var |> v)
        Nothing -> return ()
      loop $ replaceAtIndex i s a
    replaceAtIndex n item ls = a ++ (item:b) where (a, (_:b)) = Prelude.splitAt n ls

