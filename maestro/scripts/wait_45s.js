// Busy-wait for 45 seconds to allow search results to load.
// Maestro 2.2.0 removed the built-in sleep() function from evalScript.
var end = Date.now() + 45000;
while (Date.now() < end) {}
output.result = "waited 45s";
