"use strict";

function createXMLHttpRequest() {
  try { return new XMLHttpRequest(); } catch(e) {}
  try { return new ActiveXObject('Msxml2.XMLHTTP'); } catch (e) {}
  alert('XMLHttpRequest not supported');
  return null;
}

function request(i, async, succHandler, failHandler) {
  var xhr = createXMLHttpRequest();
  var url = "http://localhost:8080/"+ i;
  //console.log("XMLHttpRequest URL: "+ url);
  xhr.open("GET", url, async);
  xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
  if (async) {
    xhr.onreadystatechange = function () {
      if (xhr.readyState === 4 && xhr.status === 200) {
        var text = xhr.responseText;
        var json = JSON.parse(text);
        if (succHandler) succHandler(json);
      } else {
        if (failHandler) failHandler();
      }
    };
  }
  xhr.send();
  if (!async) {
    if (xhr.readyState === 4 && xhr.status === 200) {
      var text = xhr.responseText;
      var json = JSON.parse(text);
      return json;
    } else {
      return null;
    }
  }
}

function requestAll(callback) {
  function r(i) {
    request(i, true, function (json) {
      callback(json);
      setTimeout(function() { r(i+1); }, 10);
    });
  }
  setTimeout(function() { r(0); }, 10);
}

// Given: { ... ntg : [ { b: "D", c: "E", t: 3.0 }, ... ], ... }
// Want: { "D", "E", ... }
function jsonCars(json, props) {
  var set = {};
  for (var j = 0; j < props.length; ++j) {
    var p = props[j];
    for (var i = 0; i < json[p].length; ++i) {
      var b = json[p][i].b;
      var c = json[p][i].c;
      set[b] = true;
      set[c] = true;
    }
  }
  return Object.keys(set).sort();
}


// Given: { ... ntg : [ { b: "D", c: "E", t: 3.0 }, ... ], ... }
// Want: { "D": { "E": 3.0, ... }, ... }
function jsonToMeasurements(json, props) {
  var ms = {};
  for (var j = 0; j < props.length; ++j) {
    var p = props[j];
    if (json[p]) {
      for (var i = 0; i < json[p].length; ++i) {
        var b = json[p][i].b;
        var c = json[p][i].c;
        var t = json[p][i].t;
        if (!ms[b]) {
          ms[b] = {};
        }
        if (!ms[b][c]) {
          ms[b][c] = {};
        }
        ms[b][c][p] = t;
      }
    }
  }
  return ms;
}

function jsonToLanes(json) {
  var lanes = {};
  for (var i = 0; i < json.lane.length; ++i) {
    lanes[json.lane[i].b] = json.lane[i].l;
  }
  return lanes;
}

/* Animation object drawing in the street element with streetId.
 * The timer object is used to register events.
 * The JSON data needs to be added when it comes in using Animation.push().
 * The props parameter indicates which elements from the JSON data are used
 * to construct the initial Rstc object.
 * For each processed JSON object, the jsonCallback is called. This is quite
 * bad architecture, but the animation object is the one who `defines time.'
 */
function Animation(streetId, timer, props, jsonCallback) {
  var street = new Street(streetId, timer, 2, { offset: "25%", fps: 50, relHeight: 0.5 });
  var cars = {};

  var lanes = null;
  var rstc = null;

  this.street = function () { return street; }
  this.rstc = function () { return rstc; };

  var jsons = [];
  this.push = function (json) {
    jsons.push(json);
  };

  var tLast = 0;
  street.addRedrawHook(function (t) {
    if (jsons.length > 0 && (rstc == null || rstc.start() >= jsons[0].time)) {
      var json = jsons.shift();
      jsonCallback(json);
      if (json.action.init) {
        lanes = jsonToLanes(json);
        rstc = new ChangingRstc(new Rstc(jsonToMeasurements(json, props), json.time)).wait(0);
        rstc.forceReferenceCar("B");
        for (var id in cars) {
          cars[id].kill();
        }
        for (var id in rstc.cars) {
          (function (id) {
            cars[id] = new Elem(id, street,
              function (t) { return SCALE * rstc.x(id) + 0.5; },
              function (t) { return lanes[id]; }
            );
          })(id);
        }
      } else if (json.action.accel) {
        rstc
          .wait(json.time - rstc.start()) // synchronize time of model with observation
          .accel(json.action.accel.b, json.action.accel.q) // perform acceleration
          .progress() // for performance
          .wait(0); // to allow for efficient time counting
      } else if (json.action.lc) {
        lanes[json.action.lc.b] = json.action.lc.l;
      }
    }
    if (rstc) {
      rstc.wait(t - tLast);
      street.scroll(-1 /* * rstc.v(rstc.computeReferenceCar()) */ * t * SCALE);
    }
    tLast = t;
  });

  this.clear = function () {
    if (timer != null)
      timer.stop();
    timer = null;
    removeChildren(streetId);
  }
}


// vim:textwidth=80:shiftwidth=2:softtabstop=2:expandtab

