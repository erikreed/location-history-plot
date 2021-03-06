// Copyright (c) 2015, Erik Reed. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as Math;
import 'package:google_maps/google_maps.dart' as gm;

const int MAX_ERROR = 10000;  // max error accuracy distance

class FileDrop {
  FormElement _readForm;
  InputElement _fileInput;
  Element _dropZone;

  FileDrop() {
    _readForm = document.querySelector('#read');
    _fileInput = document.querySelector('#files');
    _fileInput.onChange.listen((e) => _onFileInputChange());

    _dropZone = document.querySelector('#drop-zone');
    _dropZone.onDragOver.listen(_onDragOver);
    _dropZone.onDragEnter.listen((e) => _dropZone.classes.add('hover'));
    _dropZone.onDragLeave.listen((e) => _dropZone.classes.remove('hover'));
    _dropZone.onDrop.listen(_onDrop);
  }

  void _onDragOver(MouseEvent event) {
    event.stopPropagation();
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  }

  void _onDrop(MouseEvent event) {
    event.stopPropagation();
    event.preventDefault();
    _dropZone.classes.remove('hover');
    _readForm.reset();
    _onFilesSelected(event.dataTransfer.files);
  }

  void _onFileInputChange() {
    _onFilesSelected(_fileInput.files);
  }

  void _onFilesSelected(List<File> files) {
    Stopwatch timer = new Stopwatch()..start();
    CoordinateManager cm = new CoordinateManager();

    var i = 0;
    for (File file in files) {
      print("Loading ${file.name}: ${(file.size / 1024 / 1024 ).toStringAsFixed(2)}MB...");

      FileReader reader = new FileReader();
      reader.onLoad.forEach((e) {
        var result = JSON.decode(reader.result);
        List locations = result['locations'];

        var coords = locations
            .where((l) => l['accuracy'] != null && l['accuracy'] <= MAX_ERROR)
            .map((l) {
              return new Coordinate(
                  l['latitudeE7'] / 1e7, l['longitudeE7'] / 1e7, int.parse(l['timestampMs']));
        }).toList();
        print('Filtered ${locations.length - coords.length} coordinates due to accuracy cap of $MAX_ERROR');
        cm.addCoords(coords);
        print("Read ${coords.length} coordinates.");
      });
      reader.readAsText(file);

      reader.onLoadEnd.forEach((e) {
        if (++i != files.length) {
          return; // TODO: this is silly
        }
        var uniqueLocs = cm.uniqueLocs();
        print(uniqueLocs.length);
        print("Time elapsed: ${timer.elapsed.toString()}");

        final mapOptions = new gm.MapOptions()
          ..zoom = 0
          ..center = new gm.LatLng(0, 0);
        var map = new gm.GMap(querySelector("#map_canvas"), mapOptions);

        var path = new gm.PolylineOptions();
        path.geodesic = true;
        path.path = uniqueLocs.map((c) => new gm.LatLng(c.lat, c.long)).toList();
        var line = new gm.Polyline(path);
        line.map = map;

        Set<String> countries = new Set<String>();
        uniqueLocs.forEach((c) {
          new gm.Marker(new gm.MarkerOptions()..position = c.toGmLatLong())..map = map;
          c.reverseGeocode().then((List<Map> o) {
            if (o == null) {
              return;
            }
            var match = o.firstWhere((Map m) {
              List<String> types = m['types'];
              return types.contains('country');
            });

            countries.add(match['name']);
            print("Country count ${countries.length}: $countries");
          });
        });
      });
    }
  }
}

class CoordinateManager {
  static const num MIN_DISTANCE_DELTA = 250; // km

  List<Coordinate> coords = [];

  CoordinateManager() {}

  void setCoords(List<Coordinate> coords) {
    this.coords = coords;
  }

  void addCoords(List<Coordinate> coords) {
    this.coords.addAll(coords);
    this.coords.sort();
  }

  List<Coordinate> uniqueLocs() {
    List<Coordinate> out = [];
    out.add(coords.first);

    for (var i = 0; i < coords.length - 1; i++) {
      var c = coords[i];
      var c2 = coords[i + 1];
      if (((c.timestamp - out.last.timestamp).abs() / 1000) > 30 * 3600 &&
          out.last.distanceTo(c) > MIN_DISTANCE_DELTA &&
          out.last.distanceTo(c2) > MIN_DISTANCE_DELTA) {
        out.add(c);
      }
    }

    return out;
  }
}

class Coordinate implements Comparable {
  static const EARTH_RADIUS = 6371; // km

  final double lat;
  final double long;
  final int timestamp;

  @override
  int compareTo(Coordinate c) {
    return timestamp - c.timestamp;
  }

  Coordinate(this.lat, this.long, this.timestamp) {}

  @override
  toString() {
    return "Coordinate <lat: $lat, long: $long, timestamp: $timestamp>";
  }

  num distanceTo(Coordinate c) {
    return getDistanceFromLatLonInKm(lat, long, c.lat, c.long);
  }

  static num getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    var R = 6371; // Radius of the earth in km
    var dLat = deg2rad(lat2 - lat1); // deg2rad below
    var dLon = deg2rad(lon2 - lon1);
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    var d = R * c; // Distance in km
    return d;
  }

  static num deg2rad(deg) {
    return deg * (Math.PI / 180);
  }

  gm.LatLng toGmLatLong() {
    return new gm.LatLng(lat, long);
  }

  Future<Object> reverseGeocode() {
    var completer = new Completer();
    Storage localStorage = window.localStorage;
    localStorage.clear();
    String key = "$lat,$long";

    var existing = localStorage[key];
    if (existing != null) {
      existing = JSON.decode(existing);
      completer.complete(existing);
    } else {
      gm.GeocoderRequest request = new gm.GeocoderRequest();
      request.location = toGmLatLong();

      gm.Geocoder geocoder = new gm.Geocoder();
      geocoder.geocode(request, (List<gm.GeocoderResult> results, gm.GeocoderStatus status) {
        if (status.$unsafe.contains("OK")) {
          var jsObjects = results.map((r) {
            var out = {};
            out['types'] = r.$unsafe['types'];
            out['name'] = r.$unsafe['formatted_address'];
            return out;
          }).toList();
          localStorage[key] = JSON.encode(jsObjects);
          completer.complete(jsObjects);
        } else {
          print('Error looking up $this: ${status.$unsafe}');
          completer.complete(null);
        }
      });
    }
    return completer.future;
  }
}

void main() {
  new FileDrop();
}
