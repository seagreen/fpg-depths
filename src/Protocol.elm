module Protocol
    exposing
        ( Message(..)
        , NetworkMessage
        , Server
        , decodeNetworkMessage
        , encodeNetworkMessage
        , send
        )

{-| Types and serialization functions used in the client-server protocol.
-}

import Dict exposing (Dict)
import Game.Type.Buildable as Buildable exposing (Buildable(..))
import Game.Type.Building as Building exposing (Building(..))
import Game.Type.Commands exposing (Commands)
import Game.Type.Habitat as Habitat
import Game.Type.Unit as Unit exposing (Submarine(..))
import HexGrid exposing (Point)
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode as Encode
import Random.Pcg as Random
import WebSocket


--------------------------------------------------------------------------------
-- Message types
{- Non-depths specific type, just used to talk to the current server.

   topic is an arbitrary String, eg a game room
-}


type alias NetworkMessage =
    { topic : String, payload : Message }


type Message
    = JoinMessage
    | StartGameMessage
        { seed : Random.Seed
        }
    | TurnMessage
        { commands : Commands
        }


type alias Server =
    { url : String
    , room : String
    }


send : Server -> Message -> Cmd msg
send server msg =
    let
        networkMsg =
            { topic = server.room
            , payload = msg
            }
    in
    WebSocket.send server.url (encodeNetworkMessage networkMsg)



--------------------------------------------------------------------------------
-- Message decoders


decodeNetworkMessage : Decoder NetworkMessage
decodeNetworkMessage =
    Decode.map2
        NetworkMessage
        (Decode.field "topic" Decode.string)
        (Decode.field "payload" decodeMessage)


decodeMessage : Decoder Message
decodeMessage =
    let
        decode : String -> Decoder Message
        decode type_ =
            case type_ of
                "join" ->
                    Decode.succeed JoinMessage

                "start-game" ->
                    Decode.field "value" decodeStartGameMessage

                "turn" ->
                    Decode.field "value" decodeTurnMessage

                _ ->
                    Decode.fail ("Unknown message type: " ++ type_)
    in
    Decode.field "type" Decode.string
        |> Decode.andThen decode


decodeStartGameMessage : Decoder Message
decodeStartGameMessage =
    Decode.map
        (\seed -> StartGameMessage { seed = seed })
        (Decode.field "seed" Random.fromJson)


decodeTurnMessage : Decoder Message
decodeTurnMessage =
    let
        decodeCommands : Decoder Commands
        decodeCommands =
            Decode.map3
                Commands
                decodeMoves
                decodeBuildOrders
                decodeHabitatNamings

        decodeMoves : Decoder (Dict Int Point)
        decodeMoves =
            Decode.field
                "moves"
                (decodeDictFromArray Decode.int decodePoint)

        decodeBuildOrders : Decoder (Dict Point Buildable)
        decodeBuildOrders =
            Decode.field
                "build_orders"
                (decodeDictFromArray decodePoint decodeBuildable)

        decodePoint : Decoder Point
        decodePoint =
            decodePair Decode.int Decode.int

        decodeHabitatNamings : Decoder (Dict Int Habitat.Name)
        decodeHabitatNamings =
            Decode.field "habitat_namings"
                (decodeDictFromArray Decode.int decodeHabitatName)
    in
    Decode.map
        (\commands -> TurnMessage { commands = commands })
        decodeCommands


decodeBuildable : Decoder Buildable
decodeBuildable =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "building" ->
                        Decode.field "payload" decodeBuilding
                            |> Decode.map BuildBuilding

                    "submarine" ->
                        Decode.field "payload" decodeSubmarine
                            |> Decode.map BuildSubmarine

                    _ ->
                        Decode.fail ("Unknown buildable: " ++ type_)
            )


decodeBuilding : Decoder Building
decodeBuilding =
    Decode.string
        |> Decode.andThen
            (\buildingStr ->
                case Building.fromString buildingStr of
                    Just building ->
                        Decode.succeed building

                    Nothing ->
                        Decode.fail ("Unknown building: " ++ buildingStr)
            )


decodeSubmarine : Decoder Submarine
decodeSubmarine =
    Decode.string
        |> Decode.andThen
            (\submarineStr ->
                case Unit.fromString submarineStr of
                    Just sub ->
                        Decode.succeed sub

                    Nothing ->
                        Decode.fail ("Unknown submarine: " ++ submarineStr)
            )


decodeHabitatName : Decoder Habitat.Name
decodeHabitatName =
    Decode.map2
        Habitat.Name
        (Decode.field "full" Decode.string)
        (Decode.field "abbreviation" Decode.string)



--------------------------------------------------------------------------------
-- Decoding helpers


decodeDictFromArray :
    Decoder comparable
    -> Decoder v
    -> Decoder (Dict comparable v)
decodeDictFromArray decodeA decodeB =
    Decode.list (decodePair decodeA decodeB)
        |> Decode.map Dict.fromList


encodeDictAsArray :
    (comparable -> Value)
    -> (v -> Value)
    -> Dict comparable v
    -> Value
encodeDictAsArray f g dict =
    Dict.toList dict
        |> List.map (encodePair f g)
        |> Encode.list


decodePair : Decoder a -> Decoder b -> Decoder ( a, b )
decodePair =
    decodePairWith (,)


decodePairWith : (a -> b -> c) -> Decoder a -> Decoder b -> Decoder c
decodePairWith f dx dy =
    Decode.map2
        f
        (Decode.index 0 dx)
        (Decode.index 1 dy)


encodePair : (a -> Value) -> (b -> Value) -> ( a, b ) -> Value
encodePair f g ( a, b ) =
    Encode.list [ f a, g b ]



--------------------------------------------------------------------------------
-- Message encoders


encodeNetworkMessage : NetworkMessage -> String
encodeNetworkMessage nm =
    Encode.encode 2
        (Encode.object
            [ ( "topic", Encode.string nm.topic )
            , ( "payload", encodeMessage nm.payload )
            ]
        )


encodeMessage : Message -> Value
encodeMessage message =
    Encode.object
        [ ( "type", encodeType message )
        , ( "value", encodeValue message )
        ]


encodeType : Message -> Value
encodeType message =
    Encode.string
        (case message of
            JoinMessage ->
                "join"

            StartGameMessage _ ->
                "start-game"

            TurnMessage _ ->
                "turn"
        )


encodeValue : Message -> Value
encodeValue message =
    case message of
        JoinMessage ->
            Encode.object []

        StartGameMessage { seed } ->
            encodeStartGameMessage seed

        TurnMessage { commands } ->
            encodeTurnMessage commands


encodeStartGameMessage : Random.Seed -> Value
encodeStartGameMessage seed =
    Encode.object [ ( "seed", Random.toJson seed ) ]


encodeTurnMessage : Commands -> Value
encodeTurnMessage commands =
    Encode.object
        [ ( "moves", encodeMoves commands.moves )
        , ( "build_orders", encodeBuildOrders commands.buildOrders )
        , ( "habitat_namings", encodeHabitatNamings commands.habitatNamings )
        ]


encodeMoves : Dict Int Point -> Value
encodeMoves =
    encodeDictAsArray Encode.int encodePoint


encodeBuildOrders : Dict Point Buildable -> Value
encodeBuildOrders =
    encodeDictAsArray encodePoint encodeBuildable


encodeHabitatNamings : Dict Int Habitat.Name -> Value
encodeHabitatNamings =
    encodeDictAsArray Encode.int encodeHabitatName


encodeBuildable : Buildable -> Value
encodeBuildable buildable =
    let
        encode : String -> Value -> Value
        encode type_ payload =
            Encode.object
                [ ( "type", Encode.string type_ )
                , ( "payload", payload )
                ]

        encodeBuilding : Building -> Value
        encodeBuilding =
            Encode.string << toString

        encodeSubmarine : Submarine -> Value
        encodeSubmarine =
            Encode.string << toString
    in
    case buildable of
        BuildBuilding building ->
            encode "building" (encodeBuilding building)

        BuildSubmarine sub ->
            encode "submarine" (encodeSubmarine sub)


encodePoint : Point -> Value
encodePoint =
    encodePair Encode.int Encode.int


encodeHabitatName : Habitat.Name -> Value
encodeHabitatName name =
    Encode.object
        [ ( "full", Encode.string name.full )
        , ( "abbreviation", Encode.string name.abbreviation )
        ]



--------------------------------------------------------------------------------
-- Sum types without arguments


buildingToString : Building -> String
buildingToString =
    toString
