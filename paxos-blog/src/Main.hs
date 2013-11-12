module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
-- Paxos Imports
import System.Console.Haskeline
import Paxos

main = runInputT defaultSettings loop
  where loop = do
          minput <- getInputLine "> "
          case minput of
            Nothing     -> return ()
            Just "exit" -> return ()
            Just input   -> do
              outputStrLn $ "Echo: " ++ input
              loop
