module Game.State exposing (..)

import Dict exposing (Dict)
import Either exposing (Either(..))
import Game.Building as Building exposing (Building(..))
import Game.Id as Id exposing (Id(..), IdSeed(..))
import Game.Unit as Unit exposing (Player(..), Submarine(..), Unit)
import HexGrid exposing (Direction, HexGrid(..), Point)
import Random.Pcg as Random


{-| The game's state.

I considered naming this `State`, but the turn resolution
code uses it alongside `State` from `folkertdev/elm-state`
so much that things got confusing.

-}
type alias Game =
    { grid : HexGrid Tile
    , turn : Turn

    -- Used for giving new units Ids. Incrmental.
    , nextUnitId : IdSeed

    -- Used for determining battle events.
    , randomSeed : Random.Seed
    }


init : Game
init =
    { grid =
        HexGrid.fromList 6
            (Tile Dict.empty Depths)
            [ ( ( -4, 1 ), emptyMountain )
            , ( ( -1, -3 ), emptyMountain )
            , ( ( 2, -4 ), emptyMountain )
            , ( ( 3, -1 ), emptyMountain )
            , ( ( 2, 2 ), emptyMountain )
            , ( ( -3, 3 ), emptyMountain )
            , ( ( -2, 4 ), emptyMountain )
            , ( ( -4, -2 )
              , Tile
                    (Dict.singleton
                        1
                        (Unit (Id 1) Player1 ColonySub)
                    )
                    Depths
              )
            , ( ( 6, 0 )
              , Tile
                    (Dict.singleton
                        2
                        (Unit (Id 2) Player2 ColonySub)
                    )
                    Depths
              )
            ]
    , turn = Turn 1
    , nextUnitId = IdSeed 3
    , randomSeed = Random.initialSeed 0
    }


initDebug : Game
initDebug =
    { grid =
        HexGrid.fromList 6
            (Tile Dict.empty Depths)
            [ ( ( -4, 1 ), Tile Dict.empty (Mountain (Just <| newHabitat Player1 (Id 1))) )
            , ( ( -1, -3 ), Tile Dict.empty (Mountain (Just <| newHabitat Player2 (Id 2))) )
            , ( ( 2, -4 ), emptyMountain )
            , ( ( 3, -1 ), emptyMountain )
            , ( ( 2, 2 ), emptyMountain )
            , ( ( -3, 3 ), emptyMountain )
            , ( ( -2, 4 ), emptyMountain )
            , ( ( -4, -2 )
              , Tile
                    (Dict.singleton
                        1
                        (Unit (Id 1) Player1 ColonySub)
                    )
                    Depths
              )
            , ( ( 6, 0 )
              , Tile
                    (Dict.singleton
                        2
                        (Unit (Id 2) Player2 ColonySub)
                    )
                    Depths
              )
            ]
    , turn = Turn 1
    , nextUnitId = IdSeed 3
    , randomSeed = Random.initialSeed 0
    }


type Turn
    = Turn Int


unTurn : Turn -> Int
unTurn (Turn n) =
    n


{-| Dict keys are the subs' Ids.
-}
type alias Tile =
    { units : Dict Int Unit
    , fixed : Geology
    }


emptyMountain : Tile
emptyMountain =
    Tile Dict.empty (Mountain Nothing)


type Geology
    = Depths
    | Mountain (Maybe Habitat)


type alias Habitat =
    { name : Either HabitatEditor HabitatName
    , player : Player

    -- Carried over from the id of the colony sub that created
    -- the habitat:
    , id : Id
    , buildings : List Building
    , producing : Maybe Buildable
    , produced : Int
    }


newHabitat : Player -> Id -> Habitat
newHabitat player colonySubId =
    { name = Left emptyNameEditor
    , player = player
    , id = colonySubId
    , buildings = [ PrefabHabitat ]
    , producing = Nothing
    , produced = 0
    }


habitatFullName : Habitat -> String
habitatFullName hab =
    case hab.name of
        Left _ ->
            "<New habitat>"

        Right name ->
            name.full


habitatAbbreviation : Habitat -> String
habitatAbbreviation hab =
    case hab.name of
        Left _ ->
            "<N>"

        Right name ->
            name.abbreviation


habitatsForPlayer : Player -> Game -> List Habitat
habitatsForPlayer player game =
    habitatDict game.grid
        |> Dict.values
        |> List.filter (\hab -> hab.player == player)


habitatDict : HexGrid Tile -> Dict Point Habitat
habitatDict (HexGrid _ grid) =
    let
        f : Point -> Tile -> Dict Point Habitat -> Dict Point Habitat
        f point tile acc =
            case tile.fixed of
                Mountain (Just hab) ->
                    Dict.insert point hab acc

                _ ->
                    acc
    in
    Dict.foldr f
        Dict.empty
        grid


habitatFromTile : Tile -> Maybe Habitat
habitatFromTile tile =
    case tile.fixed of
        Mountain (Just hab) ->
            Just hab

        Mountain Nothing ->
            Nothing

        Depths ->
            Nothing


habitatFromPoint : Point -> Dict Point Tile -> Maybe Habitat
habitatFromPoint point grid =
    Dict.get point grid
        |> Maybe.andThen habitatFromTile


updateHabitat : Point -> (Habitat -> Habitat) -> Dict Point Tile -> Dict Point Tile
updateHabitat point update grid =
    let
        updateHab : Tile -> Tile
        updateHab tile =
            case tile.fixed of
                Mountain (Just hab) ->
                    { tile | fixed = Mountain (Just (update hab)) }

                Mountain Nothing ->
                    tile

                Depths ->
                    tile
    in
    Dict.update point (Maybe.map updateHab) grid


type alias HabitatName =
    { full : String
    , abbreviation : String
    }


type HabitatEditor
    = HabitatEditor HabitatName


unHabitatEditor : HabitatEditor -> HabitatName
unHabitatEditor (HabitatEditor editor) =
    editor


emptyNameEditor : HabitatEditor
emptyNameEditor =
    HabitatEditor
        { full = ""
        , abbreviation = ""
        }


type Buildable
    = BuildSubmarine Submarine
    | BuildBuilding Building


name : Buildable -> String
name buildable =
    case buildable of
        BuildSubmarine sub ->
            (Unit.stats sub).name

        BuildBuilding building ->
            (Building.stats building).name


cost : Buildable -> Int
cost buildable =
    case buildable of
        BuildSubmarine sub ->
            (Unit.stats sub).cost

        BuildBuilding building ->
            (Building.stats building).cost


findUnit : Id -> Dict Point Tile -> Maybe ( Point, Unit )
findUnit id grid =
    let
        f : Point -> Tile -> Maybe ( Point, Unit ) -> Maybe ( Point, Unit )
        f point tile acc =
            case Dict.get (Id.unId id) tile.units of
                Nothing ->
                    acc

                Just sub ->
                    Just ( point, sub )
    in
    Dict.foldr f Nothing grid


friendlyUnits : Player -> Tile -> List Unit
friendlyUnits currentPlayer tile =
    List.filter
        (\unit -> unit.player == currentPlayer)
        (Dict.values tile.units)


{-| Get all friendly units in the game and their locations.

Returned `Int` keys are unit IDs.

-}
unitDict : Dict Point Tile -> Dict Int Point
unitDict grid =
    unitList grid
        |> List.map (\( point, unit ) -> ( Id.unId unit.id, point ))
        |> Dict.fromList


friendlyUnitDict : Player -> Dict Point Tile -> Dict Int Point
friendlyUnitDict currentPlayer grid =
    friendlyUnitList currentPlayer grid
        |> List.map (\( point, unit ) -> ( Id.unId unit.id, point ))
        |> Dict.fromList


unitList : Dict Point Tile -> List ( Point, Unit )
unitList =
    Dict.foldr
        (\point tile acc ->
            List.map (\unit -> ( point, unit )) (Dict.values tile.units) ++ acc
        )
        []


friendlyUnitList : Player -> Dict Point Tile -> List ( Point, Unit )
friendlyUnitList currentPlayer =
    List.filterMap
        (\( point, unit ) ->
            if unit.player == currentPlayer then
                Just ( point, unit )
            else
                Nothing
        )
        << unitList
