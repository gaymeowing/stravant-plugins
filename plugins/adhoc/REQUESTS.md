- How about a beveling tool? I spend a bunch of time adding cylinders on the edges then spheres on the corners, both slow and really inefficient tri-wise Something where you select a part (or maybe even a certain corner of a part) and you can bevel it, and also choose the level of detail

- A big ol button that adds a model of the Snowflake Eyes limited face to the game (snowflake eyes hype hype hype)

- (large) How about a physics-related tool where you use StepPhysics and DragDetectors (or pseudo ones) to place objects with an interface like so:
    A start simulation button that turns into a stop simulation button,
    An input box that determines the speed of the simulation,
    A list of force presets that can be placed and customized that will affect the simulation by applying forces to the involved parts (pulse, explosion, wind, magnet, random, ect.),
    A way to clear or remove placed forces,
Here's what using the plugin would look like:
    You use the interface to place force emitters,
    You select the parts you want to do a physics simulation on,
    You press the start simulation button and the simulation begins (TryBeginRecording),
    You pause the simulation and drag one of the parts to a more desirable spot using a TranslateViewPlane type of drag style,
    You change the speed of the simulation to be slower,
    You start the simulation again,
    You stop the simulation (FinishRecording)
Here's some nice additions that would make it even more polished:
    Highlight the parts being simulated with green and yellow based on the state of the simulation,
    Allow users to be able to scrub through past waypoints in the simulation while it's paused,
    Gizmos for forces emitters that show where and how they will affect parts,
    Gizmos for objects that are being simulated that show their velocity vector