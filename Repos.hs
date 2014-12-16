{-# LANGUAGE DeriveDataTypeable #-}

module Repos where

import Control.Arrow (left)
import Control.Applicative ((<*>))
import Data.Binary
import Data.Binary.Generic
import Data.Data
import Data.Functor ((<$>))
import qualified Github.Repos as GH
import qualified Github.Users as GH
import qualified Github.Users.Followers as GH
import System.Environment (getArgs)

data GHProfile =
  GHProfile [GH.Repo] [GH.GithubOwner] [GH.GithubOwner] GH.DetailedOwner
  deriving (Show, Data, Typeable)

instance (Binary GHProfile) where
  get = getGeneric
  put = putGeneric

fetchGHProfile :: String -> IO (Either String GHProfile)
fetchGHProfile username = do
  possibleRepos <- GH.userRepos username GH.Owner
  possibleFollowers <- GH.usersFollowing username
  possibleFollowing <- GH.usersFollowedBy username
  possibleUserInfo <- GH.userInfoFor username
  return $ left show $ GHProfile <$> possibleRepos
                                 <*> possibleFollowers
                                 <*> possibleFollowing
                                 <*> possibleUserInfo

main :: IO ()
main = do
  [username] <- getArgs
  result <- fetchGHProfile username
  print result
