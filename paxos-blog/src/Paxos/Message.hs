module Paxos.Message where

type Entry = String
type Value = Maybe Entry

newtype Ballot = Ballot (Int, Int) deriving (Show, Eq)

instance Ord Ballot where
  compare (Ballot (a, b)) (Ballot (c, d)) = 
    case compare a c of
      EQ -> compare b d
      o  -> o

data Message = Prepare Ballot 
             | Ack Ballot Ballot Value 
             | Accept Ballot Value 
             | Decide Value
             deriving (Show, Eq)

