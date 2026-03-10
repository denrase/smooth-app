// Busy-wait for 15 seconds to allow deep link product page to load.
// Maestro 2.2.0 removed the built-in sleep() function from evalScript.
var end = Date.now() + 15000;
while (Date.now() < end) {}
output.result = "waited 15s";
