# Location History Plot

A pure client-side location history parser/visualizer in Dart.

## Steps:
* Fetch json location history via Google Takeout
* Select it in the web-app
* The coordinates over time will be plotted on Google Maps via Javascript API.

There should be one marker/coordinate added for every 250KM or greater delta between any two
location coordinates combined with a 30 minute lack of coordinate updating. This is
a heuristic to capture only coordinates where a flight occurred and to minimize redundancy
in an easy/greedy fashion.
