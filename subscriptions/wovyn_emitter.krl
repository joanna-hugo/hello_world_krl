ruleset io.picolabs.wovyn.emitter {

  meta {
    name "wovyn_emitter"
    author "PJW"
    description "Simulates a Wovyn temperature sensor"
    use module io.picolabs.wrangler alias wrangler
    shares schedule, heartbeat_period, operating_state
  }

  global {

    schedule = function(){schedule:list()};

    heartbeat_period = function(){ent:heartbeat_period};

    operating_state = function(){ent:emitter_state};

    default_heartbeat_period = 300; //seconds

  }

  rule set_emitter_operation {
    select when emitter new_state
    if(event:attr("pause")) then noop();
    fired {
      ent:emitter_state := "paused";
    } else {
      ent:emitter_state := "running";
    }
  }

  rule set_period {
    select when emitter new_heartbeat_period
    always {
      ent:heartbeat_period := event:attr("heartbeat_period")
      .klog("Heartbeat period: "); // in seconds

    }
  }
 
  rule raise_emitter_event {
    select when emitter new_sensor_reading

    pre {

      // Bounds should not be fixed, but are for now
      period = ent:heartbeat_period.defaultsTo(20)
               .klog("Heartbeat period: "); // in seconds
      temperatureF = (random:integer(lower = 700, upper = 800)/10) // one decimal digit of precision
                     .klog("TemperatureF: ");
      temperatureC = math:round((temperatureF - 32)/1.8,1);
      healthPercent = random:integer(lower = 500, upper = 900)/10; // one decimal digit of precision
      transducerGUID = ent:transducerGUID.defaultsTo(random:uuid());
      emitterGUID = ent:emitterGUID.defaultsTo(random:uuid()); 

      genericThing = {
                    "typeId": "2.1.2",
                    "typeName": "generic.simple.temperature",
                    "healthPercent": healthPercent,
                    "heartbeatSeconds": period,
                    "data": {
                        "temperature": [
                            {
                                "name": "enclosure temperature",
                                "transducerGUID": transducerGUID,
                                "units": "degrees",
                                "temperatureF": temperatureF,
                                "temperatureC": temperatureC
                            }
                        ]
                    }
                  };

      specificThing = {
                    "make": "Wovyn ESProto",
                    "model": "Temp2000",
                    "typeId": "1.1.2.2.2000",
                    "typeName": "enterprise.wovyn.esproto.temp.2000",
                    "thingGUID": emitterGUID+".1",
                    "firmwareVersion": "Wovyn-Temp2000-1.1-DEV",
                    "transducer": [
                        {
                            "name": "Maxim DS18B20 Digital Thermometer",
                            "transducerGUID": transducerGUID,
                            "transducerType": "Maxim Integrated.DS18B20",
                            "units": "degrees",
                            "temperatureC": temperatureC
                        }
                    ],
                    "battery": {
                        "maximumVoltage": 3.6,
                        "minimumVoltage": 2.7,
                        "currentVoltage": 3.4
                    }
                };
                
     property = {
                    "name": "Wovyn_163A54",
                    "description": "Wovyn ESProto Temp2000",
                    "location": {
                        "description": "Timbuktu",
                        "imageURL": "http://www.wovyn.com/assets/img/wovyn-logo-small.png",
                        "latitude": "16.77078",
                        "longitude": "-3.00819"
                    }
                };
    }
    if ( ent:emitter_state == "running" ) then noop();
    fired {
      ent:transducerGUID := transducerGUID if ent:transducerGUID.isnull();
      ent:emitterGUID := emitterGUID if ent:emitterGUID.isnull();
      raise wovyn event "heartbeat" attributes {
        "emitterGUID": emitterGUID,
        "genericThing": genericThing,
        "specificThing": specificThing,
        "property": property
        }
    }
  }

  rule inialize_ruleset {
    select when wrangler ruleset_installed where event:attr("rids") >< meta:rid
    pre {
      period = ent:heartbeat_period
               .defaultsTo(event:attr("heartbeat_period") || default_heartbeat_period)
               .klog("Initilizing heartbeat period: "); // in seconds

    }
    if ( ent:heartbeat_period.isnull() && schedule:list().length() == 0) then send_directive("Initializing sensor pico");
    fired {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      ent:emitter_state := "running"if ent:emitter_state.isnull();

      schedule emitter event "new_sensor_reading" repeat << */#{period} * * * * * >>  attributes { }
    } 
  }

}