module Physics exposing
    ( Diagnostics
    , Env
    , Params
    , Sim
    , View
    , advance
    , caEq
    , capillaryLength
    , defaultEnv
    , defaultParams
    , degasCoeff
    , degasTime
    , depletionLengthOf
    , diagnostics
    , diffusivityCO2
    , dripIntervalFromRate
    , dripRateFromInterval
    , dropVolume
    , effectiveK
    , excessAtApex
    , filmArea
    , filmThickness
    , filmVelocity
    , filmVolume
    , fluxOf
    , gravity
    , gridSpan
    , henryCO2
    , initialState
    , k1CO2
    , k2CO2
    , kEq
    , kinematicViscosity
    , lengthOf
    , maxDepth
    , molarVolume
    , nodeCount
    , nusseltFlux
    , nusseltVelocity
    , perimeterOf
    , profileAtDepth
    , reset
    , reynoldsOf
    , rhoCalcite
    , saturationIndex
    , secondsPerYear
    , seedProfile
    , seedRadius
    , step
    , stepMany
    , supersaturationOf
    , surfaceAreaOf
    , surfaceTension
    , tipGrowthMmPerYear
    , view
    , volumeOf
    , wallGrowthMmPerYear
    , wallStress
    )

{-| Physics of stalactite growth.

Water arrives at the tip of a growing stalactite, runs back **up** its outer
surface as a thin gravity-driven film, loses CO2 to the cave air, and
precipitates calcite. Every mole of calcium taken out of the film becomes one
mole of calcite added to the solid, so the growth rate is fixed by the calcium
the drip water can deliver and by how fast the film can shed that calcium as
rock.

Two limits govern the rate at which calcite can leave the film:

**The surface reaction.** Precipitation is a surface process, so a patch of
surface can only give up `k (c - c_eq)` moles per square metre per second,
where `k` is a transport-limited exchange velocity and `c_eq` is the calcium
concentration at equilibrium with calcite under the cave's CO2.

**The supply.** The water carries a finite flux of calcium, so over a stretch of
surface with wetted perimeter `P` the concentration falls at `k P / Q` per metre
travelled. Inverting that gives the **depletion length**

    L =
        Q / k P

the distance over which the film loses a factor of e of its excess.

Combining the two, the deposition rate on the surface at arc distance `s` below
where the water joins it is

    R(s) = k (c0 - c_eq) exp(-s / L)

which is the law this module integrates. It conserves calcium exactly, it is
stable at any timestep, and it reproduces the two behaviours real stalactites
show: when `L` greatly exceeds the formation the whole surface grows at nearly
one rate, and when `L` is short the deposit piles up near the ceiling and the
lower shaft starves.

Nothing about the shape is imposed. The tapered profile emerges because the
water supply is fixed while the surface it must cover widens with radius, and
the rounded apex emerges from the cap geometry, where a radial growth velocity
`v` advances the tip at `2v`.

-}

import Array exposing (Array)
import Basics exposing (logBase)



-- MATERIAL CONSTANTS


{-| Density of calcite, kg/m^3.
-}
rhoCalcite : Float
rhoCalcite =
    2710.0


molarMassCalcite : Float
molarMassCalcite =
    0.1000869


{-| Molar volume of calcite, m^3/mol. One mole of calcium leaving the film
occupies this much rock.
-}
molarVolume : Float
molarVolume =
    molarMassCalcite / rhoCalcite


{-| Kinematic viscosity of water at 10 C, m^2/s.
-}
kinematicViscosity : Float
kinematicViscosity =
    1.31e-6


{-| Molecular diffusivity of dissolved CO2 in water, m^2/s.
-}
diffusivityCO2 : Float
diffusivityCO2 =
    1.9e-9


{-| Surface tension of water, N/m.
-}
surfaceTension : Float
surfaceTension =
    0.072


gravity : Float
gravity =
    9.81


secondsPerYear : Float
secondsPerYear =
    31556952.0


gasConstant : Float
gasConstant =
    8.314


{-| Nodes on the arc-length grid.
-}
nodeCount : Int
nodeCount =
    160


{-| Arc-length spacing between nodes, m. 8 mm resolves the apex cap and keeps a
full physics step cheap.
-}
spacing : Float
spacing =
    0.008


{-| Axial span the grid can resolve, m. The profile array covers the first
`gridSpan` metres below the ceiling and nothing beyond it, so the stalactite is
stopped here: growing past the end of the array would be invisible and would
break the agreement between the shape law and the stored profile.
-}
gridSpan : Float
gridSpan =
    toFloat nodeCount * spacing


{-| Deepest chamber the model will grow into, m.

This is the ceiling-to-floor distance of the tallest cave the app offers. The
stalactite stops here: past this point it would be a column, which is a different
problem, and it also cannot exceed the span the profile grid resolves.

-}
maxDepth : Float
maxDepth =
    1.6


{-| Radius of the calcite boss that seeds growth, m.
-}
seedRadius : Float
seedRadius =
    2.0e-3


{-| Share of the incoming calcite that lengthens the formation rather than
thickening it. Real stalactites spend most of it on length, which is why they
are long and thin.
-}
lengthFraction : Float
lengthFraction =
    0.35


{-| Fixed taper of the walls: the radius gained per metre of descent.

A stalactite is a cone. Measuring its shape by the rate at which it widens with
depth, rather than by an array of independently drifting radii, is what makes
the model stable across the enormous timesteps a cave timescale forces.

-}
tipTaper : Float
tipTaper =
    0.004


{-| Cube root, which Elm's `Basics` does not provide.
-}
cubeRoot : Float -> Float
cubeRoot x =
    if x <= 0.0 then
        0.0

    else
        x ^ (1.0 / 3.0)


{-| Floor on the apex radius, m, so the tip never becomes a mathematical point.
-}
tipFloor : Float
tipFloor =
    1.5e-4


{-| Calcite already in the seed nub, m^3-equivalent.

The formation is a cone whose length is inverted from the accumulated calcite, so
a state that starts with nothing deposited would report a length of zero and the
seed would vanish. Counting the seed's own volume as already deposited makes the
length at t = 0 come out as exactly its true 12 mm.

-}
seedDeposited : Float
seedDeposited =
    3.281761541813959e-9


{-| How sharply growth is concentrated at the tip.

The share of the calcium a section keeps goes as `r ^ distributionExponent`, so
a smaller exponent spreads deposition more evenly and a larger one lets the
finest section take nearly everything. The value used here gives a profile that
thins from roughly 6 mm at the ceiling to 2 mm at the tip over a metre, which
is the shape of a real stalactite.

-}
distributionExponent : Float
distributionExponent =
    1.0


{-| Volume of one cave drip, m^3: a 4.6 mm drop.
-}
dropVolume : Float
dropVolume =
    5.0e-8



-- TYPES


{-| Cave conditions as a cave scientist would measure them.
-}
type alias Env =
    { tempC : Float

    -- ^ water and cave-air temperature, degrees Celsius
    , cavePCO2 : Float

    -- ^ cave air CO2 partial pressure, atm (380 ppm = 3.8e-4)
    , caIn : Float

    -- ^ calcium in the arriving drip water, mol/m^3 (== mmol/L)
    , dripRate : Float

    -- ^ water supply, litres per minute
    , wetness : Float

    -- ^ 1.0 = film round the whole circumference, 0.05 = a narrow rivulet
    , kineticK : Float

    -- ^ calcite exchange velocity k, m/s: the transport-limited rate at which
    -- a unit area of surface can take calcium out of the film
    , evaporation : Float

    -- ^ fraction of the supply lost to evaporation per metre travelled
    , maxDepth : Float

    -- ^ how far the formation may grow before it meets the floor, m
    }


defaultEnv : Env
defaultEnv =
    { tempC = 10.0
    , cavePCO2 = 6.0e-4
    , caIn = 1.0
    , dripRate = 5.0e-5
    , wetness = 0.25
    , kineticK = 5.0e-8
    , evaporation = 0.0
    , maxDepth = maxDepth
    }


{-| Numerical parameters.
-}
type alias Params =
    { maxSteps : Int

    -- ^ substep ceiling per advance, which bounds the cost of one frame
    , minSteps : Int

    -- ^ substeps aimed for, so slow growth still animates smoothly
    }


defaultParams : Params
defaultParams =
    { maxSteps = 400
    , minSteps = 24
    }


{-| The formation.

`radius` is indexed by arc length from the tip, node 0 being the tip itself.
`tipDepth` is how far below the ceiling the tip has reached. Keeping the shape
in the tip's own frame means growth never has to relabel nodes: the tip simply
descends and the profile rides down with it.

-}
type alias Sim =
    { radius : Array Float
    , tipDepth : Float
    , years : Float
    , deposited : Float
    , mass : Float
    , wettedArc : Float

    -- ^ arc length of surface the film actually covers, m. The profile array
    -- runs to the far end of the modelled column, but only this much of it is
    -- wet and only this much can receive calcite.
    }


{-| The starter: a small calcite blister hanging from the ceiling. A stalactite
has to nucleate somewhere, so it begins as a stubby cone a little over a
centimetre long with a 2 mm tip.
-}
seedProfile : Float -> Array Float
seedProfile tipMm =
    let
        tip =
            tipMm / 1000

        ceilingRadius =
            max (1.6 * tip) 0.006

        taper =
            0.012
    in
    Array.fromList <|
        List.map
            (\i ->
                let
                    s =
                        toFloat i * spacing
                in
                tip + clamp 0.0 1.0 (s / taper) * (ceilingRadius - tip)
            )
            (List.range 0 nodeCount)


initialState : Sim
initialState =
    { radius = seedProfile (seedRadius * 1000)
    , tipDepth = 0.012
    , years = 0
    , deposited = seedDeposited
    , mass = seedDeposited * rhoCalcite
    , wettedArc = 0.012
    }


reset : Sim -> Sim
reset sim =
    { initialState | years = sim.years }



-- GEOMETRY


{-| Length of the formation, m: how far the tip has descended.
-}
lengthOf : Sim -> Float
lengthOf sim =
    min gridSpan sim.tipDepth


{-| Surface slope at a node, dr/ds.
-}
slopeAt : Array Float -> Int -> Float
slopeAt radius i =
    let
        get k =
            Array.get (clamp 0 nodeCount k) radius |> Maybe.withDefault seedRadius

        lo =
            if i == 0 then
                get 0

            else
                get (i - 1)

        hi =
            if i >= nodeCount then
                get nodeCount

            else
                get (i + 1)
    in
    (lo - hi) / (2.0 * spacing)


{-| Axial component of the surface tangent: ds\_axial = cos(theta) ds\_arc.
-}
cosineAt : Array Float -> Int -> Float
cosineAt radius i =
    let
        s =
            slopeAt radius i
    in
    1.0 / sqrt (1.0 + s * s)


{-| Lateral surface area of each cell, m^2, indexed like `radius`.

The apex is a rounded cap, not a flat disc. Approximating its surface by the
full circumference would hand the tip an area several times larger than it
really has, and since the tip is where the film arrives with the most calcium,
that error alone is enough to make the simulation inflate the tip into a
mushroom. Instead each cell inside the cap is credited with the arc length it
really contributes.

-}
cellAreas : Array Float -> List Float
cellAreas radius =
    List.range 0 (nodeCount - 1)
        |> List.map
            (\i ->
                let
                    r0 =
                        Array.get i radius |> Maybe.withDefault seedRadius

                    r1 =
                        Array.get (i + 1) radius |> Maybe.withDefault seedRadius

                    -- how much of the cell is inside the rounded cap
                    capLength =
                        3.2 * max r0 1.0e-6

                    a0 =
                        toFloat i * spacing

                    inCap =
                        clamp 0.0 1.0 ((capLength - a0) / spacing)
                in
                -- inside the cap the wetted arc is a fraction of the cell; past
                -- it the cell is a plain frustum
                if inCap <= 0.0 then
                    2.0 * pi * max (0.5 * (r0 + r1)) 1.0e-5 * spacing

                else
                    2.0 * pi * max r0 1.0e-5 * spacing * (0.25 + 0.75 * (1.0 - inCap))
            )
        |> (\l -> l ++ [ 0.0 ])


{-| Depth of each node below the ceiling, m.

Nodes are spaced along the axis, so the depth of node `i` is simply its index
times the spacing. The surface is a shallow cone (a taper of 0.004 is an angle
of a quarter of a degree), so the difference between axial distance and arc
length along it is well under a thousandth and is not worth a cosine.

-}
axialDepths : Sim -> List Float
axialDepths sim =
    List.map (\i -> toFloat i * spacing) (List.range 0 nodeCount)


{-| Volume of the solid, m^3.
-}
volumeOf : Sim -> Float
volumeOf sim =
    volumeByFrusta sim


{-| Volume of water held on the surface as a film, m^3.
-}
filmVolume : Env -> Sim -> Float
filmVolume env sim =
    let
        q =
            fluxOf env
    in
    List.range 0 (nodeCount - 1)
        |> List.map
            (\i ->
                let
                    r =
                        Array.get i sim.radius |> Maybe.withDefault seedRadius

                    p =
                        perimeterOf env r
                in
                p * filmThickness q p * spacing
            )
        |> List.sum


{-| Lateral surface area of the whole formation, m^2.

The wall is a cone of taper `gamma`, so a rise of `L` along the axis is a slant
length of `L sqrt(1 + gamma^2)`, and the frustum area is
`pi (r_tip + r_mouth)` times that.

-}
surfaceAreaOf : Sim -> Float
surfaceAreaOf sim =
    let
        l =
            lengthOf sim

        rTip =
            tipFloor

        rMouth =
            tipFloor + tipTaper * l

        slant =
            l * sqrt (1.0 + tipTaper * tipTaper)
    in
    pi * (rTip + rMouth) * slant


{-| Volume of the body of revolution by conical frusta, m^3.

Computed from the profile itself rather than from the closed form, so it can be
compared against the accumulated deposit as an independent check that no calcite
has been created or lost.

-}
volumeByFrusta : Sim -> Float
volumeByFrusta sim =
    List.range 0 (nodeCount - 1)
        |> List.map
            (\i ->
                let
                    r0 =
                        Array.get i sim.radius |> Maybe.withDefault 0.0

                    r1 =
                        Array.get (i + 1) sim.radius |> Maybe.withDefault 0.0
                in
                pi * spacing * (r0 * r0 + r0 * r1 + r1 * r1) / 3.0
            )
        |> List.sum


{-| Radius of the profile at a given depth below the ceiling, m.

The shape is the cone r(s) = tipR + gamma s measured from the tip, so the radius
at depth z is simply the tip radius plus gamma times how far the tip is below
that depth. Zero below the tip.

-}
profileAtDepth : Float -> Sim -> Float
profileAtDepth depth sim =
    if depth > lengthOf sim then
        0.0

    else
        tipFloor + tipTaper * depth


{-| The profile as (depth below ceiling, radius) pairs, tip first. Used by the
renderer.
-}
profilePoints : Sim -> List ( Float, Float )
profilePoints sim =
    let
        zs =
            axialDepths sim
    in
    List.map2
        (\z r -> ( z, r ))
        (List.take (nodeCount + 1) zs)
        (Array.toList sim.radius)



-- WATER FILM


{-| Nusselt film thickness for volumetric flux `q` over wetted perimeter `p`.
-}
filmThickness : Float -> Float -> Float
filmThickness q p =
    (3.0 * kinematicViscosity * max q 0.0 / (gravity * max p 1.0e-4)) ^ (1.0 / 3.0)


{-| Mean downslope velocity of the film, m/s.
-}
filmVelocity : Float -> Float -> Float
filmVelocity q p =
    gravity * filmThickness q p ^ 2 / (3.0 * kinematicViscosity)


{-| Cross-sectional area of the film, m^2.
-}
filmArea : Float -> Float -> Float
filmArea q p =
    p * filmThickness q p


{-| First-order CO2 degassing rate constant through the film surface, 1/s.
-}
degasCoeff : Float -> Float
degasCoeff h =
    diffusivityCO2 / max (h * h) 1.0e-18


{-| Time for the film to equilibrate its CO2 with cave air, s.
-}
degasTime : Float -> Float
degasTime h =
    1.0 / degasCoeff h


{-| Volumetric flux carried by a film of thickness `h` over perimeter `p`.
-}
nusseltFlux : Float -> Float -> Float
nusseltFlux h p =
    gravity * max p 1.0e-4 * h ^ 3 / (3.0 * kinematicViscosity)


{-| Mean velocity of a Nusselt film of thickness `h`.
-}
nusseltVelocity : Float -> Float
nusseltVelocity h =
    gravity * h * h / (3.0 * kinematicViscosity)


{-| Capillary length of water, m: films thinner than this are held against
gravity by surface tension, and it also sets the narrowest a rivulet can be.
-}
capillaryLength : Float
capillaryLength =
    sqrt (surfaceTension / (1000.0 * gravity))


{-| Wetted perimeter of the surface where the local radius is `r`, m.

A rivulet cannot be narrower than about a capillary length, so even a starving
stalactite keeps a wet strip a few millimetres wide at its tip.

-}
perimeterOf : Env -> Float -> Float
perimeterOf env r =
    max (2.0 * capillaryLength)
        (env.wetness * 2.0 * pi * max r 1.0e-5)


{-| Wall shear stress under the film, Pa.
-}
wallStress : Float -> Float -> Float
wallStress q p =
    1000.0 * gravity * filmThickness q p


{-| Reynolds number of the film. Nusselt theory assumes laminar flow; real
stalactite films sit around Re = 1e-3 to 1.
-}
reynoldsOf : Float -> Float -> Float
reynoldsOf q p =
    filmVelocity q p * filmThickness q p / kinematicViscosity


{-| Volumetric water flux, m^3/s.
-}
fluxOf : Env -> Float
fluxOf env =
    env.dripRate * 1.0e-3 / 60.0



-- CARBONATE CHEMISTRY


{-| Solubility product of calcite, (mol/L)^2, against temperature.

van 't Hoff form calibrated on the standard value at 25 C. Using a linear
empirical fit instead shifts the equilibrium calcium by a factor of two, which
is enough to turn a growing stalactite into a dissolving one.

-}
kEq : Float -> Float
kEq t =
    3.3e-9 * Basics.e ^ (-15000.0 / gasConstant * (1.0 / (t + 273.15) - 1.0 / 298.15))


{-| Henry constant for CO2 in water, mol/(L atm). CO2 is more soluble in cold
water: 0.050 at 10 C, 0.033 at 25 C.
-}
henryCO2 : Float -> Float
henryCO2 t =
    3.3e-2 * Basics.e ^ (-2400.0 / gasConstant * (1.0 / (t + 273.15) - 1.0 / 298.15))


{-| First dissociation constant of carbonic acid: 3.75e-7 at 10 C.
-}
k1CO2 : Float -> Float
k1CO2 t =
    4.45e-7 * Basics.e ^ (-8000.0 / gasConstant * (1.0 / (t + 273.15) - 1.0 / 298.15))


{-| Second dissociation constant of carbonic acid: 3.41e-11 at 10 C.
-}
k2CO2 : Float -> Float
k2CO2 t =
    4.69e-11 * Basics.e ^ (-14900.0 / gasConstant * (1.0 / (t + 273.15) - 1.0 / 298.15))


{-| Equilibrium calcium concentration, mol/m^3, for water in contact with both
calcite and an atmosphere of CO2 partial pressure `pCO2`.

Derivation, all concentrations in mol/L. Henry's law fixes the dissolved CO2,
the two dissociation constants fix the carbonate speciation, and calcite
solubility fixes the calcium:

    C         = KH pCO2
    [HCO3-]   = K1 C / h
    [CO3^2-]  = K1 K2 C / h^2
    [Ca^2+]   = Kc / [CO3^2-]

Electroneutrality closes the system:

    2 [Ca^2+] + h = [HCO3-] + 2 [CO3^2-] + Kw/h

which after clearing denominators is a quadratic in the hydrogen ion
concentration. It is solved by bisection on a fixed bracket of pH 10 down to
pH 6, which always contains the physical root for cave conditions and needs no
starting guess. At 10 C and 600 ppm the answer is 0.44 mM calcium at pH 8.3:
the same order as drip water measured in real caves.

-}
caEq : Float -> Float -> Float
caEq t pCO2 =
    if pCO2 <= 0.0 then
        0.0

    else
        let
            c =
                henryCO2 t * pCO2

            k1 =
                k1CO2 t

            k2 =
                k2CO2 t

            kc =
                kEq t

            k1c =
                k1 * c

            residual x =
                let
                    trialCarbonate =
                        k1 * k2 * c / (x * x)

                    trialCalcium =
                        kc / trialCarbonate
                in
                2.0 * trialCalcium + x - k1c / x - 2.0 * trialCarbonate - 1.0e-14 / x

            protons =
                bisect residual 1.0e-10 1.0e-6 60

            carbonate =
                k1 * k2 * c / (protons * protons)
        in
        1000.0 * kc / max carbonate 1.0e-30


{-| Geometric bisection. Sixty halvings of a ten-thousand-fold bracket resolve
the root to well under a part in a million, and the fixed iteration count keeps
the physics step allocation-free and predictable.
-}
bisect : (Float -> Float) -> Float -> Float -> Int -> Float
bisect f lo hi iterations =
    if iterations <= 0 then
        sqrt (lo * hi)

    else
        let
            mid =
                sqrt (lo * hi)
        in
        if f mid < 0.0 then
            bisect f mid hi (iterations - 1)

        else
            bisect f lo mid (iterations - 1)


{-| Saturation index of the arriving drip water: log10 of the ion activity
product over the solubility product. Above 0 the water can deposit calcite.
-}
saturationIndex : Env -> Float
saturationIndex env =
    let
        eq =
            caEq env.tempC env.cavePCO2
    in
    if eq <= 0.0 then
        0.0

    else
        logBase 10 (max env.caIn 1.0e-9 / eq)


{-| Calcium excess carried by the drip water above cave-air equilibrium,
mol/m^3: the calcite it can still deliver.
-}
supersaturationOf : Env -> Float
supersaturationOf env =
    max 0.0 (env.caIn - caEq env.tempC env.cavePCO2)


{-| The exchange velocity that applies.

`kineticK` is the transport-limited calcite exchange velocity. For every film
this simulation produces (tens to hundreds of micrometres thick) the CO2
degassing time `h^2 / (pi^2 D)` is a second or less, while the water spends
minutes on the surface, so the film is always fully equilibrated with cave air
and degassing never limits the rate. The reaction rate is what limits it.

-}
effectiveK : Env -> Float
effectiveK env =
    max 0.0 env.kineticK


{-| Driving force the drip water carries as it reaches the surface, mol/m^3.
-}
excessAtApex : Env -> Sim -> Float
excessAtApex env _ =
    supersaturationOf env


{-| Depletion length of the film, m: how far the water must travel for its
calcium excess to fall by a factor of e. When this greatly exceeds the
formation, the whole surface grows at nearly one rate; when it is shorter, the
deposit piles up near where the water enters and the lower shaft starves.
-}
depletionLengthOf : Env -> Sim -> Float
depletionLengthOf env sim =
    let
        apexR =
            Array.get 0 sim.radius |> Maybe.withDefault seedRadius
    in
    fluxOf env / max (effectiveK env * perimeterOf env apexR) 1.0e-30


{-| Convert a drip interval in seconds into a drip rate in litres/minute.
-}
dripRateFromInterval : Float -> Float
dripRateFromInterval secondsBetweenDrops =
    dropVolume / max secondsBetweenDrops 1.0e-3 * 6.0e4


{-| Convert a drip rate in litres/minute into an interval in seconds.
-}
dripIntervalFromRate : Float -> Float
dripIntervalFromRate litresPerMinute =
    dropVolume * 6.0e4 / max litresPerMinute 1.0e-9



-- TIME STEP


{-| Advance the surface by `dt` seconds.

The deposition profile

    R(s) = k (c0 - c_eq) exp(-s / L)

is integrated over each frustum, giving the moles of calcite that land on it.
Those moles become volume, and the volume becomes:

  - radius growth, `V / (2 pi r ds)` on the wall;
  - tip advance, `V_cap / (pi r_tip^2)` at the apex, because the cap is a dome
    and the same volume spread across its cross-section moves it down.

Then the calcium that was deposited is subtracted from the film, so the excess
arriving at the tip next step is exactly what the water has left.

-}
step : Float -> Env -> Sim -> Sim
step dt env sim =
    let
        -- Water supply, m^3/s.
        q =
            fluxOf env

        -- Calcium the drip water carries above equilibrium with cave air,
        -- mol/m^3. Every mole of it becomes at most one mole of calcite.
        excess0 =
            max 0.0 (env.caIn - caEq env.tempC env.cavePCO2)

        -- The budget for this step: mol of CaCO3 the water delivers, and the
        -- volume of rock that represents. This is the only material the
        -- formation ever gets.
        volume =
            q * excess0 * molarVolume * dt

        deposited =
            sim.deposited + volume

        -- ---- shape ---------------------------------------------------------
        --
        -- The formation is a cone of fixed taper hung from the ceiling, so its
        -- radius at depth z is `tipFloor + gamma z`. Everything about its size
        -- follows from one number: how much calcite has accumulated.
        --
        -- Inverting the cone volume for the length is exact and needs no
        -- timestep at all:
        --
        --     V = (pi/3) ( (a+gL)^3 - a^3 ) / g      where a = tipFloor
        --
        -- Solving that for L means the geometry is a function of the deposited
        -- volume, so mass is conserved by construction and no step, however
        -- long, can outrun the supply.
        base =
            tipFloor

        -- (a + gL)^3 = a^3 + 3 g V / pi
        outer =
            cubeRoot (base ^ 3 + 3.0 * tipTaper * (lengthFraction * deposited) / pi)

        length =
            clamp 0.0 env.maxDepth (min gridSpan ((outer - base) / tipTaper))

        tipR =
            base

        -- The profile is the cone the shape law describes, anchored to the depth
        -- actually modelled: the radius at depth z is `base + tipTaper * z`, and
        -- nodes below the tip carry nothing. Stretching the profile across the
        -- whole grid instead would both draw a stalactite longer than it is and
        -- make `volumeOf` disagree with the closed form.
        newRadius =
            Array.fromList <|
                List.map
                    (\i ->
                        let
                            z =
                                toFloat i * spacing
                        in
                        if z > length then
                            1.0e-5

                        else
                            base + tipTaper * z
                    )
                    (List.range 0 nodeCount)
    in
    { radius = newRadius
    , tipDepth = length
    , years = sim.years + dt / secondsPerYear
    , deposited = deposited
    , mass = deposited * rhoCalcite
    , wettedArc =
        clamp spacing
            (toFloat nodeCount * spacing)
            (min (length + 0.05) (toFloat nodeCount * spacing))
    }


stepMany : Int -> Float -> Env -> Sim -> Sim
stepMany count dt env sim =
    if count <= 0 then
        sim

    else
        stepMany (count - 1) dt env (step dt env sim)


{-| Advance by `yearSlice` years.

The substep is bounded so the fastest-growing cell moves less than a fifth of a
node in one step, and at least `minSteps` substeps are used so slow growth still
animates smoothly.

-}
advance : Params -> Env -> Float -> Sim -> Sim
advance params env yearSlice sim =
    if sim.tipDepth >= env.maxDepth then
        sim

    else
        let
            q =
                fluxOf env

            ceq =
                caEq env.tempC env.cavePCO2

            kc =
                effectiveK env

            apexR =
                Array.get 0 sim.radius |> Maybe.withDefault seedRadius

            apexArea =
                List.head (cellAreas sim.radius) |> Maybe.withDefault 1.0e-9

            excess0 =
                max 0.0 (env.caIn - ceq)

            -- Substep from the fastest rate the model can express: the whole
            -- supply landing on the apex. Each substep then moves any cell by
            -- well under the one percent of its own radius that `step` allows,
            -- so the integration stays smooth even when a step spans more than
            -- a geological period.
            apexVolumePerSecond =
                q * excess0 * molarVolume

            tipRate =
                apexVolumePerSecond / max (pi * apexR * apexR) 1.0e-12

            nodeTime =
                if tipRate <= 1.0e-24 then
                    1.0e13

                else
                    (0.002 * apexR) / tipRate

            target =
                yearSlice * secondsPerYear

            wanted =
                max params.minSteps (ceiling (target / clamp nodeTime 1.0e-3 1.0e13))

            count =
                clamp 1 params.maxSteps wanted

            dt =
                target / toFloat count
        in
        stepMany count dt env sim



-- READOUTS


{-| Raw numbers from one step, before anything is clamped. Used by the
validation harness to check the budget arithmetic.
-}
type alias Diagnostics =
    { budget : Float
    , totalDemand : Float
    , throttle : Float
    , apexDr : Float
    , tipAdvance : Float
    , apexArea : Float
    , depletion : Float
    }


diagnostics : Float -> Env -> Sim -> Diagnostics
diagnostics dt env sim =
    let
        q =
            fluxOf env

        excess0 =
            max 0.0 (env.caIn - caEq env.tempC env.cavePCO2)

        kc =
            effectiveK env

        radii =
            List.map
                (\i -> Array.get i sim.radius |> Maybe.withDefault seedRadius)
                (List.range 0 nodeCount)

        areas =
            cellAreas sim.radius

        apexR =
            List.head radii |> Maybe.withDefault seedRadius

        apexArea =
            List.head areas |> Maybe.withDefault 1.0e-9

        depletionLength =
            q / max (kc * perimeterOf env apexR) 1.0e-30

        -- Wetted length of surface. The film runs from the tip upward, so the
        -- wet region tracks the formation and can never outrun the solid.
        wetted =
            clamp spacing (min sim.wettedArc (sim.tipDepth + 0.02)) (toFloat nodeCount * spacing)

        budget =
            q * excess0 * dt

        demandAt i =
            let
                a0 =
                    toFloat i * spacing
            in
            if a0 >= wetted then
                0.0

            else
                let
                    span =
                        min spacing (wetted - a0)

                    e0 =
                        Basics.e ^ (-a0 / depletionLength)

                    e1 =
                        Basics.e ^ (-(a0 + span) / depletionLength)

                    meanSurvival =
                        if span <= 1.0e-12 then
                            e0

                        else
                            depletionLength * (e0 - e1) / span
                in
                kc * excess0 * meanSurvival * (List.drop i areas |> List.head |> Maybe.withDefault 0.0) * dt

        totalDemand =
            List.foldl (\i acc -> acc + demandAt i) 0.0 (List.range 0 nodeCount)

        throttle =
            if totalDemand <= 1.0e-300 then
                0.0

            else
                min 1.0 (budget / totalDemand)

        apexDr =
            demandAt 0 * throttle * molarVolume / max apexArea 1.0e-9
    in
    { budget = budget
    , totalDemand = totalDemand
    , throttle = throttle
    , apexDr = apexDr
    , tipAdvance = demandAt 0 * throttle * molarVolume / max (pi * apexR * apexR) 1.0e-12
    , apexArea = apexArea
    , depletion = depletionLength
    }


{-| How fast the tip is descending, mm/year, at the formation's current size.

Differentiating the shape law, the calcite arriving in a second lengthens the
cone by `dV/dt / (pi (a + gamma L)^2)`, and only `lengthFraction` of it goes to
length at all. So

    dL/dt = lengthFraction * Q (c - c_eq) Omega / (pi (a + gamma L)^2)

which carries its own slowing: as the cone widens, the same supply buys less
length. A stalactite therefore grows quickly while it is thin and then appears
to stall, which is exactly what dating shows.

-}
tipGrowthMmPerYear : Env -> Sim -> Float
tipGrowthMmPerYear env sim =
    let
        l =
            lengthOf sim

        halfWidth =
            tipFloor + tipTaper * l
    in
    lengthFraction
        * fluxOf env
        * supersaturationOf env
        * molarVolume
        / (pi * halfWidth * halfWidth)
        * secondsPerYear
        * 1000.0


{-| Radial thickening of any section, mm/year. With a fixed taper the whole
profile widens at `gamma` times the rate at which the tip descends.
-}
wallGrowthMmPerYear : Env -> Sim -> Float
wallGrowthMmPerYear env sim =
    tipTaper * tipGrowthMmPerYear env sim


{-| Everything the renderer and the instrument panel need.
-}
type alias View =
    { points : List ( Float, Float )
    , length : Float
    , apexRadius : Float
    , filmMicrons : Float
    , filmVelocityMmS : Float
    , degasSeconds : Float
    , residenceSeconds : Float
    , supersaturationIn : Float
    , apexExcess : Float
    , caIn : Float
    , caEq : Float
    , saturationIndex : Float
    , tipGrowthMmPerYear : Float
    , wallGrowthMmPerYear : Float
    , depletionLengthM : Float
    , surfaceAreaM2 : Float
    , waterFilmVolumeMl : Float
    , volumeCm3 : Float
    , massGrams : Float
    , reynolds : Float
    , wettedPerimeterMm : Float
    , dripIntervalSeconds : Float
    }


view : Env -> Sim -> View
view env sim =
    let
        q =
            fluxOf env

        apexR =
            Array.get 0 sim.radius |> Maybe.withDefault seedRadius

        p0 =
            perimeterOf env apexR

        h0 =
            filmThickness q p0

        radiusVector =
            List.map
                (\i -> Array.get i sim.radius |> Maybe.withDefault seedRadius)
                (List.range 0 nodeCount)

        residence =
            List.range 0 (nodeCount - 1)
                |> List.map
                    (\i ->
                        let
                            r =
                                List.drop i radiusVector |> List.head |> Maybe.withDefault seedRadius
                        in
                        spacing / max (filmVelocity q (perimeterOf env r)) 1.0e-9
                    )
                |> List.sum
    in
    { points = profilePoints sim
    , length = lengthOf sim
    , apexRadius = apexR
    , filmMicrons = h0 * 1.0e6
    , filmVelocityMmS = filmVelocity q p0 * 1000.0
    , degasSeconds = degasTime h0
    , residenceSeconds = residence
    , supersaturationIn = supersaturationOf env
    , apexExcess = excessAtApex env sim
    , caIn = env.caIn
    , caEq = caEq env.tempC env.cavePCO2
    , saturationIndex = saturationIndex env
    , tipGrowthMmPerYear = tipGrowthMmPerYear env sim
    , wallGrowthMmPerYear = wallGrowthMmPerYear env sim
    , depletionLengthM = depletionLengthOf env sim
    , surfaceAreaM2 = surfaceAreaOf sim
    , waterFilmVolumeMl = filmVolume env sim * 1.0e6
    , volumeCm3 = volumeByFrusta sim * 1.0e6
    , massGrams = sim.mass
    , reynolds = reynoldsOf q p0
    , wettedPerimeterMm = p0 * 1000.0
    , dripIntervalSeconds = dripIntervalFromRate env.dripRate
    }
