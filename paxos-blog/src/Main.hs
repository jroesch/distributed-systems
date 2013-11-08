module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
import Control.Monad.State

type ReplicaState = Boolean
type Replica a = StateT ReplicaState IO a

newValueRef :: (Value v) => IO (IORef (Just v))
newValueRef = newIORef Nothing

main :: IO ()
main = do
  ballotNum <- newIORef (0, 0)
  acceptNum <- newIORef (0, 0)
  acceptVal <- newValueRef
  channels <- replicateM newChan
  let peers = M.fromList $ zip [1..] channels
  
prepare :: Integer -> Chan a -> IO ()
prepare c = undefined

class Value a where
  repr :: a = undefined

promise :: (Value a) => Integer -> Integer -> a
  

leaderWait leader

