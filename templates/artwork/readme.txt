I use yellow as the template color because it's the brightest on
the wheel.  The CSS filters...

filter: hue-rotate(120deg);

... only support rotating an existing color.  If it's anything
but yellow to start off with, the resulting color ends up dim, 
and you have to amplify the color brightness as well as the
rotate the color. 
