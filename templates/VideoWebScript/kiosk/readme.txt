This template generates a video player that expects to be in a 'full screen'
window, all of the time.

What we do is switch between play list and player mode, instead of full screen
and windowed mode.

There are two reasons for this behavior.  The first is '--kiosk' flag in 
Chrome (Windows only).  That puts the browser up on a page, with no external
navigation controls.

The second reason is the 'You are in full screen' idiot prompt that has gained
popularity among lazy browser programmers, in some cases (like Chrome, from the
file system) where it can never be disabled at all.  Because you apparently can't
remember between clicking on the 'full screen' icon, and seeing it go to a full-
screen window, that you put it into full-screen.  So they take care to remind 
you of this with a popup that must be clicked.  Every.  Single.  Time.

I know it's supposed to be a 'security' feature, just like car alarms that go off  
in the middle of the night for no reason, or arresting children for pointing 
their fingers 'like a gun'.  Just in case!
