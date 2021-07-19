{-# LANGUAGE TemplateHaskell #-}
module Obelisk.State where

import Obelisk.Math.Homogenous
import Obelisk.Engine.Input

import Control.Lens
import Prelude hiding (map)
import Linear
import Foreign.C.Types
import Data.Array

--In the style of https://github.com/jxv/diner/library/DinoRo-rush/blob/mastush/State.hs
data PVars = PVars {
                position :: V2 Double,
                direction :: V2 Double,
                camera_plane :: V2 Double
             } deriving (Show)

data WallType = EW | FW | DW --Empty Wall, Full Wall, Door Wall
    deriving (Show, Eq)

data WorldTiles = WorldTiles {
                    mapTiles :: Array Int WallType,
                    worldSize :: CInt
                  }
    deriving Show

accessMap :: WorldTiles -> Int -> Int -> WallType
accessMap world x y = mapTiles world ! ((x * fromIntegral (worldSize world)) + y)

checkAt :: Vars -> V2 Int -> WallType
checkAt gs (V2 x y) = accessMap (world gs) x y

inBounds :: Vars -> V2 Int -> Bool
inBounds gs (V2 x y) = x >= 0 && y >= 0 && x < limit && y < limit
    where limit = fromIntegral . worldSize . world $ gs

rFW :: [WallType]
rFW = repeat FW
rEW :: [WallType]
rEW = repeat EW

--ACCESSED godBoltMap !! y !! x style
godboltMap :: WorldTiles
godboltMap = WorldTiles map 10
    where map = listArray (0, 10*10 - 1) $ concat [take 10 rFW,
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              take 3 rFW ++ [DW] ++ [FW] ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              [FW,DW] ++ take 3 rFW ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ take 4 rFW ++ [DW, FW],
              FW : take 8 rEW ++ [FW],
              FW : take 8 rEW ++ [FW],
              take 10 rFW]

boxMap :: WorldTiles
boxMap = WorldTiles map 10
    where map = listArray (0, 99) $ concat [take 10 rFW,
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 FW : take 8 rEW ++ [FW],
                 take 10 rFW
                ]

data Vars = Vars {
                player :: PVars,
                world :: WorldTiles,
                --Debug vars TODO refactor
                rotateToPView :: Bool,
                vInput :: Input
            }
    deriving Show

initPVars :: PVars
initPVars = PVars (V2 2.5 6.5) dir cam
    where
        -- dir = normalize (V2 0.8 0.330)
        -- cam = normalize $ dir *! rotation2 (-pi/2)
        dir = V2 0.8817506897247581 0.4717157207152668
        cam = V2 (-0.4717157207152668) 0.8817506897247581

initVars :: Vars
initVars = Vars initPVars godboltMap False initInput

makeClassy ''Vars
makeClassy ''PVars
makeClassy ''WorldTiles

instance HasPVars Vars where
    pVars = lens player (\v s -> v { player = s})

instance HasWorldTiles Vars where
    worldTiles = lens world (\v s -> v { world = s})