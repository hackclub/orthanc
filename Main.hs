{-# LANGUAGE TemplateHaskell, DeriveGeneric, DeriveDataTypeable,
  UnicodeSyntax #-}

import Control.Arrow (left)
import Control.Applicative (liftA3)
import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Monad (forever, forM_, sequence)
import Data.Binary
import Data.Typeable
import GHC.Generics (Generic)
import qualified Github.Users as Github
import qualified Github.Users.Followers as Github
import qualified Github.Data.Definitions as Github
import System.Environment (getArgs)

data GithubProfile = GithubProfile {
  id :: Int
  ,login :: String
  ,email :: Maybe String
  ,name :: Maybe String
  ,company :: Maybe String
  ,publicGists :: Int
  ,followers :: [Int]
  ,following :: [Int]
  ,hireable :: Maybe Bool
  ,blog :: Maybe String
  ,publicRepos :: Int
  ,location :: Maybe String
  ,url :: String
  ,avatarUrl :: String
  } deriving (Show, Generic, Typeable)

instance Binary GithubProfile

makeProfile :: [Github.GithubOwner] -> [Github.GithubOwner] ->
  Github.DetailedOwner -> GithubProfile
makeProfile followers following userInfo = GithubProfile {
      Main.id=Github.detailedOwnerId userInfo
      ,login=Github.detailedOwnerLogin userInfo
      ,email=Github.detailedOwnerEmail userInfo
      ,name=Github.detailedOwnerName userInfo
      ,company=Github.detailedOwnerCompany userInfo
      ,publicGists=Github.detailedOwnerPublicGists userInfo
      ,followers=map Github.githubOwnerId followers
      ,following=map Github.githubOwnerId following
      ,hireable=Github.detailedOwnerHireable userInfo
      ,blog=Github.detailedOwnerBlog userInfo
      ,publicRepos=Github.detailedOwnerPublicRepos userInfo
      ,location=Github.detailedOwnerLocation userInfo
      ,url=Github.detailedOwnerHtmlUrl userInfo
      ,avatarUrl=Github.detailedOwnerAvatarUrl userInfo
      }

analyzeGithub :: String -> IO (Either String GithubProfile)
analyzeGithub username = do
  possibleFollowers <- Github.usersFollowing username
  possibleFollowing <- Github.usersFollowedBy username
  possibleUserInfo <- Github.userInfoFor username

  let profile = liftA3 makeProfile possibleFollowers possibleFollowing
                  possibleUserInfo

  return $ left show profile

slave :: (ProcessId, ProcessId) -> Process ()
slave (master, workQueue) = do
    us <- getSelfPid
    go us
  where
    go us = do
      send workQueue us
      receiveWait
        [ match $ \nm -> liftIO(analyzeGithub nm) >>= send master >> go us
        , match $ \() -> return ()
        ]

remotable ['slave]

accProfiles :: Int -> Process [Either String GithubProfile]
accProfiles = go []
  where
    go :: [Either String GithubProfile] -> Int ->
      Process [Either String GithubProfile]
    go acc 0 = return $ reverse acc
    go acc n = do
      m <- expect
      go (m : acc) (n - 1)

master :: [String] -> [NodeId] -> Process [Either String GithubProfile]
master usernames slaves = do
  us <- getSelfPid
  workQueue <- spawnLocal $ do
    sequence $ map (\u -> expect >>= \them->send them u) usernames
    forever $ expect >>= \pid -> send pid ()

  forM_ slaves $ \nid -> spawn nid ($(mkClosure 'slave) (us, workQueue))
  accProfiles $ length usernames

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

main :: IO ()
main = do
  args <- getArgs

  case args of
    ("master" : host : port : usernames) -> do
      backend <- initializeBackend host port rtable
      startMaster backend $ \slaves -> do
        result <- master usernames slaves
        liftIO $ print result

    ["slave", host, port] -> do
      backend <- initializeBackend host port rtable
      startSlave backend

    _ -> putStrLn "Bad args"
