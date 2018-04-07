module Main exposing (..)

import Html
import Keyboard
import Model
import Protocol
import Update
import View
import WebSocket


enter : Int
enter =
    13


main : Program Never Model.Model Model.Msg
main =
    Html.program
        { init = ( Model.init, Model.newRandomSeed )
        , update = Update.update
        , view = View.view
        , subscriptions = subscriptions
        }


subscriptions : Model.Model -> Sub Model.Msg
subscriptions model =
    let
        keydown =
            Keyboard.downs
                (\keyPress ->
                    if keyPress == enter then
                        Model.EndRound
                    else
                        Model.NoOp
                )
    in
        case model.gameType of
            Model.NotPlayingYet _ ->
                Sub.none

            Model.SharedComputer ->
                keydown

            Model.Online { server, room } ->
                Sub.batch
                    [ keydown
                    , WebSocket.listen server Model.Recv
                    ]
