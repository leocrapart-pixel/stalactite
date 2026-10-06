port module Main exposing (main)

{-| **Stalactite** — how a cave formation actually grows.

Water arrives at the tip, runs back up the surface as a thin gravity-driven
film, loses CO2 to the cave air, and precipitates calcite. Every mole of
calcium taken out of the film becomes one mole of calcite added to the solid,
so the growth rate is governed by the calcium the drip water can deliver and by
how fast the film can shed CO2.

Nothing about the shape is imposed. The tapered profile emerges because the
water supply is fixed while the surface that water must cover widens with
radius, and the rounded apex emerges from the cap geometry. The readout panel
reports the quantities the model is really using — film thickness, CO2
degassing time, supersaturation, Reynolds number — so the result can be
checked rather than trusted.

-}

import Browser
import Browser.Events
import Canvas as C
import Html exposing (Html)
import Html.Attributes as A
import Json.Encode as E
import Physics as P exposing (Env, Params, Sim)
import Scene
import Ui


port renderScene : E.Value -> Cmd msg


port canvasResized : (Int -> msg) -> Sub msg



-- MODEL


type alias Model =
    { env : Env
    , sim : Sim
    , params : Params
    , running : Bool
    , speed : Float

    -- ^ simulated years per real second
    , clock : Float

    -- ^ real seconds since load, drives the drip animation
    , dripInterval : Float
    , presetName : String
    , history : List ( Float, Float )
    , lastSample : Float
    , viewportW : Float
    , showRings : Bool
    , stalagmiteM : Float
    , chamberM : Float
    }


type alias Preset =
    { name : String
    , blurb : String
    , env : Env
    , stalagmiteM : Float
    , chamberM : Float
    }


presets : List Preset
presets =
    [ { name = "Cave chamber"
      , blurb = "A steady, well-fed drip: half a millimole of excess lime, one drop every 42 minutes."
      , env =
            { tempC = 10
            , cavePCO2 = 6.0e-4
            , caIn = 1.0
            , dripRate = 2.0e-5
            , wetness = 0.25
            , kineticK = 5.0e-8
            , evaporation = 0
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.05
      , chamberM = 1.6
      }
    , { name = "Starving drip"
      , blurb = "An old cave with almost no supply: dense, very hard calcite, and a very long wait."
      , env =
            { tempC = 11
            , cavePCO2 = 5.0e-4
            , caIn = 0.72
            , dripRate = 3.0e-6
            , wetness = 0.15
            , kineticK = 5.0e-8
            , evaporation = 0
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.03
      , chamberM = 1.6
      }
    , { name = "Well fed"
      , blurb = "Plenty of water and lime. This one builds a metre in a few hundred thousand years."
      , env =
            { tempC = 12
            , cavePCO2 = 6.0e-4
            , caIn = 1.6
            , dripRate = 5.0e-4
            , wetness = 0.35
            , kineticK = 8.0e-8
            , evaporation = 0
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.1
      , chamberM = 1.6
      }
    , { name = "Tropical cave"
      , blurb = "Warm water holds less CO₂ and calcite kinetics run faster, but the extra CO₂ in the air works against it."
      , env =
            { tempC = 22
            , cavePCO2 = 9.0e-4
            , caIn = 1.7
            , dripRate = 1.5e-4
            , wetness = 0.3
            , kineticK = 6.0e-8
            , evaporation = 0
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.06
      , chamberM = 1.6
      }
    , { name = "Drafty passage"
      , blurb = "Dry air sweeps through, so evaporation deposits calcite alongside degassing."
      , env =
            { tempC = 9
            , cavePCO2 = 3.0e-4
            , caIn = 1.1
            , dripRate = 4.0e-5
            , wetness = 0.2
            , kineticK = 5.0e-8
            , evaporation = 0.6
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.04
      , chamberM = 1.6
      }
    , { name = "Undersaturated"
      , blurb = "Drip water poorer in lime than cave air allows. Nothing can be deposited at all."
      , env =
            { tempC = 10
            , cavePCO2 = 3.0e-3
            , caIn = 0.7
            , dripRate = 2.0e-5
            , wetness = 0.25
            , kineticK = 5.0e-8
            , evaporation = 0
            , maxDepth = 1.6
            }
      , stalagmiteM = 0.0
      , chamberM = 1.6
      }
    ]


firstPreset : Preset
firstPreset =
    List.head presets
        |> Maybe.withDefault
            { name = "Custom"
            , blurb = ""
            , env = P.defaultEnv
            , stalagmiteM = 0.05
            , chamberM = 1.0
            }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { env = firstPreset.env
      , sim = P.initialState
      , params = P.defaultParams
      , running = True
      , speed = 80000
      , clock = 0
      , dripInterval = P.dripIntervalFromRate firstPreset.env.dripRate
      , presetName = firstPreset.name
      , history = [ ( 0, P.seedRadius * 1000 ) ]
      , lastSample = 0
      , viewportW = 640
      , showRings = True
      , stalagmiteM = firstPreset.stalagmiteM
      , chamberM = firstPreset.chamberM
      }
    , render
        { width = 620
        , height = 720
        , env = firstPreset.env
        , sim = P.initialState
        , time = 0
        , chamberM = firstPreset.chamberM
        , showRings = True
        , stalagmiteM = firstPreset.stalagmiteM
        }
    )



-- MESSAGES


type Msg
    = Tick Float
    | Toggle
    | SetSpeed Float
    | ApplyPreset Preset
    | SetDripRate Float
    | SetDripInterval Float
    | SetCa Float
    | SetTemp Float
    | SetPCO2 Float
    | SetWetness Float
    | SetK Float
    | SetEvap Float
    | ResetShape
    | ToggleRings
    | SetChamber Float
    | Viewport Int
    | Noop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

        Tick dtMs ->
            let
                dt =
                    clamp 0.0 0.1 (dtMs / 1000)

                clock2 =
                    model.clock + dt
            in
            if model.running then
                let
                    slice =
                        clamp 0.0 40000 (model.speed * dt)

                    sim2 =
                        P.advance model.params model.env slice model.sim

                    grain =
                        max 500.0 (sim2.years / 140)

                    shouldSample =
                        sim2.years - model.lastSample >= grain
                in
                ( { model
                    | clock = clock2
                    , sim = sim2
                    , history =
                        if shouldSample then
                            List.take 140 (( sim2.years, apexMm sim2 ) :: model.history)

                        else
                            model.history
                    , lastSample =
                        if shouldSample then
                            sim2.years

                        else
                            model.lastSample
                  }
                , render (sceneOptions { model | env = model.env, sim = sim2 })
                )

            else
                ( { model | clock = clock2 }
                , render (sceneOptions model)
                )

        Toggle ->
            ( { model | running = not model.running }, Cmd.none )

        SetSpeed s ->
            ( { model | speed = s }, Cmd.none )

        ApplyPreset p ->
            ( { model
                | env = p.env
                , presetName = p.name
                , dripInterval = P.dripIntervalFromRate p.env.dripRate
                , sim = P.initialState
                , stalagmiteM = p.stalagmiteM
                , chamberM = p.chamberM
                , history = [ ( 0, P.seedRadius * 1000 ) ]
                , lastSample = 0
              }
            , render
                (sceneOptions
                    { model
                        | env = p.env
                        , sim = P.initialState
                        , stalagmiteM = p.stalagmiteM
                        , chamberM = p.chamberM
                    }
                )
            )

        SetDripRate r ->
            ( { model | env = setRate r model.env, dripInterval = P.dripIntervalFromRate r }
            , render (sceneOptions { model | env = setRate r model.env })
            )

        SetDripInterval s ->
            ( { model | env = setRate (P.dripRateFromInterval s) model.env, dripInterval = s }
            , render (sceneOptions { model | env = setRate (P.dripRateFromInterval s) model.env })
            )

        SetCa v ->
            ( { model | env = setCa v model.env }, render (sceneOptions { model | env = setCa v model.env }) )

        SetTemp v ->
            ( { model | env = setTemp v model.env }, render (sceneOptions { model | env = setTemp v model.env }) )

        SetPCO2 v ->
            ( { model | env = setCO2 v model.env }, render (sceneOptions { model | env = setCO2 v model.env }) )

        SetWetness v ->
            ( { model | env = setWet v model.env }, render (sceneOptions { model | env = setWet v model.env }) )

        SetK v ->
            ( { model | env = setK v model.env }, render (sceneOptions { model | env = setK v model.env }) )

        SetEvap v ->
            ( { model | env = setEvap v model.env }, render (sceneOptions { model | env = setEvap v model.env }) )

        ResetShape ->
            ( { model | sim = P.reset model.sim, history = [ ( 0, P.seedRadius * 1000 ) ], lastSample = 0 }
            , render (sceneOptions { model | sim = P.reset model.sim })
            )

        ToggleRings ->
            ( { model | showRings = not model.showRings }, render (sceneOptions { model | showRings = not model.showRings }) )

        SetChamber v ->
            ( { model | chamberM = v }, render (sceneOptions { model | chamberM = v }) )

        Viewport w ->
            ( { model | viewportW = toFloat w }, Cmd.none )



-- RENDERING


{-| Build the scene description and hand it to the canvas through the port.
-}
render : Scene.Options -> Cmd Msg
render opts =
    renderScene (C.encodeDraw (Scene.draw opts))


{-| The state the renderer needs, gathered from the model.
-}
sceneOptions : Model -> Scene.Options
sceneOptions model =
    { width = 620
    , height = 720
    , env = model.env
    , sim = model.sim
    , time = model.clock
    , chamberM = model.chamberM
    , showRings = model.showRings
    , stalagmiteM = model.stalagmiteM
    }


{-| Keep the animation clock bounded so the drip phase never loses precision
in a long session.
-}
clampTime : Model -> Float
clampTime model =
    if model.clock > 1.0e7 then
        0

    else
        model.clock



-- FIELD UPDATES
--
-- Elm does not allow a record update nested inside a record literal, so each
-- settable field gets a named function. These are trivially small but they
-- keep the `update` branches readable.


setRate : Float -> Env -> Env
setRate v env =
    { env | dripRate = v }


setCa : Float -> Env -> Env
setCa v env =
    { env | caIn = v }


setTemp : Float -> Env -> Env
setTemp v env =
    { env | tempC = v }


setCO2 : Float -> Env -> Env
setCO2 v env =
    { env | cavePCO2 = v }


setWet : Float -> Env -> Env
setWet v env =
    { env | wetness = v }


setK : Float -> Env -> Env
setK v env =
    { env | kineticK = v }


setEvap : Float -> Env -> Env
setEvap v env =
    { env | evaporation = v }



-- LOG-SCALE SLIDERS
--
-- Drip rates span four orders of magnitude, so the slider position is a
-- fraction of a cube: x^3 maps 0..1 onto the chosen minimum..maximum, which
-- gives fine control at the slow end where it matters.


rateMin : Float
rateMin =
    5.0e-7


rateMax : Float
rateMax =
    2.0e-3


rateToSlider : Float -> Float
rateToSlider r =
    clamp 0.0 1.0 ((clamp rateMin rateMax r / rateMin) ^ (1.0 / 3.0) - 1.0)


sliderToRate : Float -> Float
sliderToRate x =
    rateMin * (1.0 + clamp 0.0 1.0 x) ^ 3


intervalMin : Float
intervalMin =
    100.0


intervalMax : Float
intervalMax =
    8.0e5


intervalToSlider : Float -> Float
intervalToSlider s =
    clamp 0.0 1.0 (logBase 10 (clamp intervalMin intervalMax s / intervalMin) / logBase 10 (intervalMax / intervalMin))


sliderToInterval : Float -> Float
sliderToInterval x =
    intervalMin * (intervalMax / intervalMin) ^ clamp 0.0 1.0 x


formatRateText : Float -> String
formatRateText r =
    if r < 0.001 then
        String.fromFloat (thousandths (r * 1.0e6)) ++ " nL / min"

    else
        String.fromFloat (thousandths r) ++ " mL / min"


formatInterval : Float -> String
formatInterval s =
    if s < 90 then
        String.fromInt (round s) ++ " s"

    else if s < 5400 then
        String.fromFloat (hundredths (s / 60)) ++ " min"

    else
        String.fromFloat (hundredths (s / 3600)) ++ " h"


apexMm : Sim -> Float
apexMm sim =
    1000 * (2.0 * (P.view P.defaultEnv sim).apexRadius)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Stalactite — the physics of cave growth"
    , body =
        [ Html.div
            [ A.style "min-height" "100vh"
            , A.style "background" "#05070a"
            , A.style "color" Ui.ink
            , A.style "font" "13px ui-sans-serif, system-ui, sans-serif"
            , A.style "display" "flex"
            , A.style "flex-direction" "column"
            , A.style "gap" "12px"
            , A.style "padding" "16px 16px 28px"
            , A.style "box-sizing" "border-box"
            ]
            [ header model
            , Html.div
                [ A.style "display" "flex"
                , A.style "gap" "14px"
                , A.style "align-items" "flex-start"
                , A.style "flex-wrap" "wrap"
                , A.style "justify-content" "center"
                ]
                [ leftColumn model
                , stage model
                , rightColumn model
                ]
            ]
        ]
    }


header : Model -> Html Msg
header model =
    Html.div
        [ A.style "display" "flex"
        , A.style "justify-content" "space-between"
        , A.style "align-items" "flex-end"
        , A.style "gap" "16px"
        , A.style "flex-wrap" "wrap"
        , A.style "max-width" "1600px"
        , A.style "width" "100%"
        , A.style "margin" "0 auto"
        ]
        [ Html.div [ A.style "display" "flex", A.style "flex-direction" "column", A.style "gap" "3px" ]
            [ Html.div
                [ A.style "font" "600 20px ui-sans-serif, system-ui, sans-serif"
                , A.style "letter-spacing" "-0.015em"
                ]
                [ Html.text "Stalactite" ]
            , Html.div
                [ A.style "font" "11.5px ui-sans-serif, system-ui, sans-serif"
                , A.style "color" Ui.dim
                ]
                [ Html.text "calcite growth solved from the calcium budget of a thin water film" ]
            ]
        , Html.div
            [ A.style "display" "flex"
            , A.style "gap" "8px"
            , A.style "align-items" "center"
            , A.style "flex-wrap" "wrap"
            ]
            [ Ui.badge Ui.water ("elapsed " ++ formatYears model.sim.years)
            , Ui.badge Ui.accent model.presetName
            ]
        ]


leftColumn : Model -> Html Msg
leftColumn model =
    Html.div
        [ A.style "width" "312px"
        , A.style "flex" "0 0 312px"
        , A.style "display" "flex"
        , A.style "flex-direction" "column"
        , A.style "gap" "12px"
        ]
        [ Ui.sheet
            [ Ui.section "Run"
                [ Ui.buttonRow
                    [ Ui.button model.running
                        (if model.running then
                            "❚❚  Pause"

                         else
                            "▶  Run"
                        )
                        Toggle
                    , Ui.button False "⟲  New stalactite" ResetShape
                    , Ui.button model.showRings "≡  Years" ToggleRings
                    ]
                , Ui.slider
                    { label = "Time-lapse"
                    , value = model.speed * 1.0e-3
                    , min = 1
                    , max = 2000
                    , step = 1
                    , format = \v -> formatSpeed (v * 1.0e3)
                    , note = Just "Simulated cave time per real second. A stalactite needs hundreds of thousands of years."
                    , onInput = \v -> SetSpeed (v * 1.0e3)
                    }
                , Ui.slider
                    { label = "Chamber height"
                    , value = model.chamberM
                    , min = 0.4
                    , max = 2.4
                    , step = 0.05
                    , format = \v -> String.fromFloat (hundredths v) ++ " m"
                    , note = Just "Ceiling to floor. When the tip reaches the floor it becomes a column."
                    , onInput = SetChamber
                    }
                ]
            , Ui.rule
            , Ui.section "Water supply"
                [ Ui.slider
                    { label = "Drip rate"
                    , value = model.env.dripRate
                    , min = 0.001
                    , max = 1.5
                    , step = 0.001
                    , format = \v -> String.fromFloat (thousandths v) ++ " mL / min"
                    , note =
                        Just
                            ("one drop every "
                                ++ String.fromInt (round model.dripInterval)
                                ++ " s  ·  "
                                ++ String.fromFloat (hundredths (model.env.dripRate * 525.6))
                                ++ " L / yr"
                            )
                    , onInput = SetDripRate
                    }
                , Ui.slider
                    { label = "Drip interval"
                    , value = clamp 0.02 1.0 (intervalToSlider model.dripInterval)
                    , min = 0.02
                    , max = 1.0
                    , step = 0.005
                    , format = \_ -> formatInterval model.dripInterval
                    , note = Just "The same supply read as a rhythm. Real cave drips run from a second to a day."
                    , onInput = \v -> SetDripInterval (sliderToInterval v)
                    }
                , Ui.slider
                    { label = "Surface wetness"
                    , value = model.env.wetness
                    , min = 0.02
                    , max = 1.0
                    , step = 0.01
                    , format = \v -> String.fromInt (round (v * 100)) ++ " % of circumference"
                    , note = Just "A starving stalactite carries a narrow rivulet; a well-fed one is sheathed."
                    , onInput = SetWetness
                    }
                ]
            ]
        , Ui.sheet
            [ Ui.section "Water chemistry"
                [ Ui.slider
                    { label = "Calcium in drip water"
                    , value = model.env.caIn
                    , min = 0.2
                    , max = 8.0
                    , step = 0.05
                    , format = \v -> String.fromFloat (hundredths v) ++ " mmol / L"
                    , note = Just "Set by limestone dissolution along the flow path: usually 1–3."
                    , onInput = SetCa
                    }
                , Ui.slider
                    { label = "Cave air CO₂"
                    , value = model.env.cavePCO2 * 1.0e6
                    , min = 200
                    , max = 6000
                    , step = 25
                    , format = \v -> String.fromInt (round v) ++ " ppm"
                    , note = Just "Drip water equilibrates to this, which fixes the calcium it cannot keep."
                    , onInput = \v -> SetPCO2 (v * 1.0e-6)
                    }
                , Ui.slider
                    { label = "Temperature"
                    , value = model.env.tempC
                    , min = 0
                    , max = 30
                    , step = 0.5
                    , format = \v -> String.fromFloat (hundredths v) ++ " °C"
                    , note = Just "Calcite is less soluble in warm water, but so is CO₂."
                    , onInput = SetTemp
                    }
                , Ui.slider
                    { label = "Deposition coefficient k"
                    , value = model.env.kineticK * 1.0e9
                    , min = 5
                    , max = 500
                    , step = 1
                    , format = \_ -> String.fromFloat (thousandths (model.env.kineticK * 1.0e9)) ++ " nm / s"
                    , note = Just "Exchange velocity k. Literature values for calcite in thin films run from 0.4 to 10 mm/s; the effective rate over a whole stalactite is far smaller."
                    , onInput = \v -> SetK (v * 1.0e-9)
                    }
                , Ui.slider
                    { label = "Evaporation"
                    , value = model.env.evaporation
                    , min = 0
                    , max = 1
                    , step = 0.05
                    , format = \v -> String.fromInt (round (v * 100)) ++ " %"
                    , note = Just "Only in dry, draughty passages. A second, non-CO₂ growth path."
                    , onInput = SetEvap
                    }
                ]
            ]
        , Ui.sheet
            [ Ui.section "Cave analogues"
                (List.concatMap
                    (\p ->
                        [ Ui.button (p.name == model.presetName) p.name (ApplyPreset p)
                        , Html.div
                            [ A.style "font" "10px ui-sans-serif, system-ui, sans-serif"
                            , A.style "color" Ui.faint
                            , A.style "line-height" "1.45"
                            , A.style "margin" "-2px 0 6px 2px"
                            ]
                            [ Html.text p.blurb ]
                        ]
                    )
                    presets
                )
            ]
        ]


rightColumn : Model -> Html Msg
rightColumn model =
    let
        v =
            P.view model.env model.sim

        warning =
            v.saturationIndex <= 0.05
    in
    Html.div
        [ A.style "width" "330px"
        , A.style "flex" "0 0 330px"
        , A.style "display" "flex"
        , A.style "flex-direction" "column"
        , A.style "gap" "12px"
        ]
        [ Ui.sheet
            [ Ui.section "Growth"
                [ Ui.row "tip advance"
                    (formatRate v.tipGrowthMmPerYear)
                    (if warning then
                        Ui.warn

                     else
                        Ui.accent
                    )
                , Ui.row "wall thickening" (formatRate v.wallGrowthMmPerYear) Ui.ink
                , Ui.row "thickness ÷ length" (String.fromFloat (hundredths (v.apexRadius * 2000)) ++ " mm per " ++ String.fromFloat (hundredths (v.length * 100)) ++ " cm") Ui.dim
                , Ui.row "length" (String.fromFloat (hundredths (v.length * 100)) ++ " cm") Ui.ink
                , Ui.row "tip diameter" (String.fromFloat (thousandths (v.apexRadius * 2000)) ++ " mm") Ui.ink
                , Ui.row "calcite deposited" (formatMass v.massGrams) Ui.ink
                , Ui.row "surface area" (String.fromFloat (thousandths (v.surfaceAreaM2 * 1.0e4)) ++ " cm²") Ui.dim
                , Ui.row "elapsed" (formatYears model.sim.years) Ui.dim
                , if warning then
                    Ui.hint "⚠ The drip water is at or below calcite equilibrium for this cave air, so nothing can precipitate. Raise the calcium or lower the CO₂."

                  else
                    Ui.hint "The tip advances twice as fast as the wall thickens, because the apex is a dome: the same volume spread over its cross-section moves it further."
                ]
            ]
        , Ui.sheet
            [ Ui.section "Water film"
                [ Ui.row "thickness" (String.fromFloat (hundredths v.filmMicrons) ++ " µm") Ui.water
                , Ui.row "downslope speed" (String.fromFloat (thousandths v.filmVelocityMmS) ++ " mm / s") Ui.water
                , Ui.row "wetted perimeter" (String.fromFloat (thousandths v.wettedPerimeterMm) ++ " mm") Ui.water
                , Ui.row "CO₂ degassing time" (formatSeconds v.degasSeconds) Ui.water
                , Ui.row "film residence time" (formatSeconds v.residenceSeconds) Ui.water
                , Ui.row "Reynolds number" (formatSmall v.reynolds) Ui.dim
                , Ui.hint <|
                    if v.degasSeconds < v.residenceSeconds then
                        "The film sheds its CO₂ long before it leaves the surface, so the water finishes the climb close to equilibrium."

                    else
                        "The film is too thick to finish degassing: the water still carries excess CO₂ at the tip."
                ]
            ]
        , Ui.sheet
            [ Ui.section "Chemistry"
                [ Ui.row "calcium arriving" (String.fromFloat (hundredths v.caIn) ++ " mmol / L") Ui.ok
                , Ui.row "at equilibrium with cave air" (String.fromFloat (thousandths v.caEq) ++ " mmol / L") Ui.dim
                , Ui.row "excess at the tip" (String.fromFloat (thousandths v.apexExcess) ++ " mmol / L") Ui.accent
                , Ui.row "saturation index"
                    (String.fromFloat (hundredths v.saturationIndex))
                    (if warning then
                        Ui.warn

                     else
                        Ui.ok
                    )
                , Ui.row "depletion length L = Q / kP" (String.fromFloat (hundredths v.depletionLengthM) ++ " m") Ui.accent
                , Ui.bar (v.apexExcess / 5.0) Ui.accent
                , Ui.hint <|
                    if v.depletionLengthM > v.length * 1.5 then
                        "L is longer than the formation, so the film still carries excess calcium when it reaches the tip: the whole surface grows, and the tip runs ahead."

                    else
                        "L is shorter than the formation, so most of the calcium is spent near the ceiling and the lower shaft starves."
                , Ui.hint "SI = log₁₀(Ca / Ca_eq). Cave drip waters run from about 0.3 to 1.2."
                ]
            ]
        , Ui.sheet
            [ Ui.section "Growth curve"
                [ chart model
                , Ui.hint "Tip diameter against elapsed time. The curve flattens as the widening tip spreads the same water over more surface."
                ]
            ]
        , Ui.sheet
            [ Ui.section "What the model solves"
                [ Ui.row "supply" "q from the drip rate" Ui.dim
                , Ui.row "film" "Nusselt  h ∝ (νq/gP)^⅓" Ui.dim
                , Ui.row "degassing" "k = D/h²" Ui.dim
                , Ui.row "deposition" "R = k(c − c_eq)" Ui.dim
                , Ui.row "profile" "R(s) = R₀ e^(−s/L)" Ui.dim
                , Ui.row "growth" "V = R·A·dt / Ω" Ui.dim
                , Ui.hint "Equilibrium calcium is solved from the full carbonate system by bisection. 160 nodes along the surface, 8 mm apart."
                ]
            ]
        ]


stage : Model -> Html Msg
stage model =
    let
        w =
            620

        h =
            720
    in
    Html.div
        [ A.style "position" "relative"
        , A.style "flex" "1 1 420px"
        , A.style "min-width" "320px"
        , A.style "max-width" "780px"
        , A.style "border-radius" "12px"
        , A.style "overflow" "hidden"
        , A.style "border" ("1px solid " ++ Ui.faint)
        , A.style "background" "#06080b"
        ]
        [ Html.node "canvas"
            [ A.id "stage"
            , A.width w
            , A.height h
            , A.style "display" "block"
            , A.style "width" "100%"
            , A.style "height" "auto"
            ]
            []
        , Html.div
            [ A.style "position" "absolute"
            , A.style "top" "10px"
            , A.style "left" "14px"
            , A.style "font" "500 10px ui-monospace, monospace"
            , A.style "letter-spacing" "0.14em"
            , A.style "text-transform" "uppercase"
            , A.style "color" Ui.faint
            ]
            [ Html.text "cave chamber · cross-section" ]
        , Html.div
            [ A.style "position" "absolute"
            , A.style "top" "10px"
            , A.style "right" "14px"
            , A.style "font" "600 10px ui-monospace, monospace"
            , A.style "letter-spacing" "0.1em"
            , A.style "color" Ui.dim
            ]
            [ Html.text
                (if model.running then
                    "×  " ++ formatSpeed model.speed

                 else
                    "paused"
                )
            ]
        ]


{-| A small line chart of tip diameter against time, drawn with plain divs.
-}
chart : Model -> Html Msg
chart model =
    let
        ys =
            List.map Tuple.second model.history

        yMax =
            max 3.0 (List.maximum ys |> Maybe.withDefault 3.0)

        n =
            List.length model.history
    in
    Html.div
        [ A.style "position" "relative"
        , A.style "height" "92px"
        , A.style "border-left" ("1px solid " ++ Ui.faint)
        , A.style "border-bottom" ("1px solid " ++ Ui.faint)
        , A.style "margin-top" "2px"
        ]
        [ Html.div
            [ A.style "position" "absolute"
            , A.style "inset" "0"
            , A.style "display" "flex"
            , A.style "align-items" "flex-end"
            , A.style "gap" "1px"
            , A.style "padding" "0 1px"
            ]
            (model.history
                |> List.reverse
                |> List.map
                    (\point ->
                        let
                            frac =
                                clamp 0.0 1.0 (Tuple.second point / yMax)
                        in
                        Html.div
                            [ A.style "flex" "1 1 0"
                            , A.style "height" (String.fromFloat (max 1.0 (frac * 100)) ++ "%")
                            , A.style "background"
                                (C.rgba 224 176 112 (0.25 + 0.6 * (toFloat (List.length model.history) / toFloat n)))
                            , A.style "border-radius" "1px 1px 0 0"
                            ]
                            []
                    )
            )
        , Html.div
            [ A.style "position" "absolute"
            , A.style "top" "-2px"
            , A.style "right" "2px"
            , A.style "font" "600 9.5px ui-monospace, monospace"
            , A.style "color" Ui.faint
            ]
            [ Html.text (String.fromFloat (hundredths yMax) ++ " mm") ]
        ]



-- FORMATTING


formatSpeed : Float -> String
formatSpeed v =
    if v >= 1000 then
        String.fromFloat (hundredths (v / 1000)) ++ " kyr / s"

    else
        String.fromInt (round v) ++ " yr / s"


formatYears : Float -> String
formatYears y =
    if y < 1000 then
        String.fromInt (round y) ++ " years"

    else if y < 1.0e6 then
        String.fromFloat (hundredths (y / 1000)) ++ " kyr"

    else
        String.fromFloat (hundredths (y / 1.0e6)) ++ " Myr"


formatRate : Float -> String
formatRate mmPerYear =
    if mmPerYear >= 10 then
        String.fromFloat (hundredths mmPerYear) ++ " mm / yr"

    else if mmPerYear >= 0.01 then
        String.fromFloat (thousandths mmPerYear) ++ " mm / yr"

    else
        String.fromFloat (thousandths (mmPerYear * 1000)) ++ " µm / yr"


formatSeconds : Float -> String
formatSeconds s =
    if s < 0.001 then
        String.fromFloat (thousandths (s * 1.0e6)) ++ " µs"

    else if s < 1 then
        String.fromFloat (thousandths (s * 1000)) ++ " ms"

    else if s < 120 then
        String.fromFloat (hundredths s) ++ " s"

    else
        String.fromFloat (hundredths (s / 60)) ++ " min"


formatSmall : Float -> String
formatSmall x =
    if x == 0 then
        "0"

    else if abs x < 0.001 || abs x >= 100000 then
        String.fromFloat (thousandths (x * 1.0e3)) ++ "e-3"

    else
        String.fromFloat (thousandths x)


formatMass : Float -> String
formatMass kilograms =
    if kilograms < 1.0e-6 then
        String.fromFloat (thousandths (kilograms * 1.0e9)) ++ " µg"

    else if kilograms < 1.0e-3 then
        String.fromFloat (hundredths (kilograms * 1.0e6)) ++ " mg"

    else if kilograms < 1.0 then
        String.fromFloat (hundredths (kilograms * 1000)) ++ " g"

    else
        String.fromFloat (hundredths kilograms) ++ " kg"


hundredths : Float -> Float
hundredths x =
    toFloat (round (x * 100)) / 100


thousandths : Float -> Float
thousandths x =
    toFloat (round (x * 1000)) / 1000



-- SUBSCRIPTIONS AND MAIN


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onAnimationFrameDelta Tick
        , canvasResized Viewport
        ]


main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
