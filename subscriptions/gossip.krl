ruleset gossip{
    meta {
      name "Gossip"
      description "implements heterarchal gossip protocol"
      author "Joanna Hugo"
      use module io.picolabs.wrangler alias wrangler
      use module io.picolabs.subscription alias subs

      shares violations, state, snapshot, picoID, scheduled_events, selectPeer
      provides picoID, scheduled_events, addNewTemp
    }
  
    global{

        state = function(){
            ent:state
        }

        violations = function(){
            {
                "this pico status" : ent:violationStatus,
                "systemStatus": ent:violationCount
            }
        }

        snapshot = function(){
            {
                "violations": ent:violationCount,
                "violationStatus": ent:violationStatus,
                "state" :   ent:state,
                "seqID" :   ent:seqID,
                "picoID":   ent:picoID,
                "processing": ent:processing,
                "peers":    ent:knownPicos,
                "heartbeat period" : ent:period,
                "allTemps": ent:allTemps
            }
        }

        picoID = function(){
            ent:picoID
        }

        scheduled_events = function(){
            schedule:list()
        }

        selectPeer = function(){
            we_know = ent:state{[ent:picoID, ent:picoID]}.klog("number of events we know:")

            temp = ent:state.map(function(val, key) { val{key} }).klog("peers know:")
            diff = temp.filter(function(val, key) {val < we_know}).klog("difference between this and other nodes:")
            _index =  random:integer (diff.length()-1) //.klog("random index:")
            diff.keys()[_index]  || ent:knownPicos.keys()[0]
        }

        peerIsInNeed = function(target){
            // if we know more than they do 
            ent:state{ent:picoID}{ent:picoID} > ent:state{target}{ent:picoID}
        }

        addNewTemp = function(picoID, temp){
            myTemps = ent:allTemps{picoID}.klog("temps for this pico before updating:")
            myTemps.append(temp).klog("updated temps:")
        }
        
        getSeqIDFromMsg = function(msg){
            msgID = msg{"MessageID"}//.klog("msg in parsing func")
            vals = msgID.split(re#:#)
            vals[1]//.klog("parsed seqID")
        }

        addNewPeerToOwnState = function(picoID){
            currentState = ent:state{ent:picoID}
            newState = currentState.put(picoID, 0)
            newState 
        }
    }


    rule updateOwnTempsManual{
        select when gossipDebug newTemp
        pre{
            temp = event:attrs{"temp"}.klog("temp:")
            this_pico = ent:picoID
            seqID = ent:seqID
        }

        always{
            ent:allTemps{this_pico} := addNewTemp(this_pico, temp)
            ent:state{[this_pico, this_pico]} := ent:state{[this_pico, this_pico]} + 1 
            ent:seqID := ent:seqID + 1
        }
    }

    rule resetViolations{
        select when gossip resetViolOnly
        always{
            ent:violationStatus := -1
            ent:violationCount := 0
        }
    }


    rule onViolation{
        select when api temp_violations or wovyn:threshold_violation
        if ent:violationStatus.klog("current violation status:") < 0 then noop() //before status = -1, 0 --> STILL inviolation or no violation
        fired{
            ent:violationStatus := 1.klog("new violation status:")
            raise gossip event "violationStatusUpdated"
        }
        else{
            ent:violationStatus := 0.klog("new violation status:")
        }
    }

    rule onCoolTemp{
        select when wovyn heartbeat 
        pre{
            temp = event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureF"}.klog("tempF:")
        }
        if ent:violationStatus <= 0 && temp < 75 then noop() //TODO threshold == 75
        fired{
            ent:violationStatus := -1
            raise gossip event "violationStatusUpdated"
        }
    }
    /*
    rule onViolStatusUpdated{
        select when gossip violationStatusUpdated
        // broadcast update to all peers
        foreach ent:knownPicos setting (eci, id )
        pre{
            log = eci.klog("eci:")
            logger = id.klog("id:")
        }

        event:send ({ 
            "eci": eci, 
            "eid": "seen message", // can be anything, used for correlation
            "domain": "gossip", "type": "systemViolationUpdate",
            "attrs": {
              "update" : ent:violationStatus
            }
          })

        always{
            ent:violationCount := ent:violationCount + ent:violationStatus
            raise gossip event "stuff" attributes{"eci":eci}

        }
    }

    rule onSystemUpdate{
        select when gossip systemViolationUpdate
        pre{
            update = event:attrs{"update"}
        }
        always{
            ent:violationCount := (ent:violationCount + update).klog("updated system violation count:")
        } 
    }
    */


    rule reset{
        select when gossip reset
        always{
            ent:seqID := 0
            ent:period := 20
            ent:processing := true
            peerArray = subs:established("Tx_role", "node").klog("knownPicos:") || {}
            ent:knownPicos := {}

            ent:allTemps := {}
            ent:allTemps{ent:picoID} := []

            ent:violationStatus := -1
            ent:violationCount := 0
            
            ent:state := {}
            ent:state{ent:picoID} := {}
            ent:zeroState := {}
            raise gossip event "state_initiated"
            raise gossip event "stop_heartbeat"
            raise gossip event "start_heartbeat"
        }
    }

    rule on_rumor{
        select when gossip rumor
        pre{
            msg = event:attrs{"rumorMsg"}.klog("rumor msg:")
            seqID = getSeqIDFromMsg(event:attrs{"rumorMsg"}).as("Number").klog("seqID:")
            picoID = event:attrs{"rumorMsg"}{"SensorID"}.klog("sensorID:") //FROM picoID
            temp =event:attrs{"rumorMsg"}{"Temperature"}.klog("temp:")
            myState = ent:state{ent:picoID}.klog("my state:")
            violStatus = event:attrs{"violationStatus"}.klog("peer's violation status:")
        }
        if ent:processing  then noop()
        fired{
            ent:allTemps{picoID} := addNewTemp(picoID, temp) // add temp to storage 
            ent:state{[ent:picoID, picoID]} := seqID       // iterate state 
            ent:state{[picoID, picoID]} := seqID
            ent:violationCount := (ent:violationCount + violStatus).klog("updated violation count")
        }
    }

    rule on_seen{
        select when gossip:seen
        pre{
            msg = event:attrs{"seenMsg"}.klog("seen msg:")
            picoID = event:attrs{"povID"}
            violationCount = event:attrs{"violationCount"}.klog("peers violation count" )
        }
        if ent:processing then noop()
        fired{
            ent:state{picoID} := msg
            ent:violationCount := violationCount
        }
    }

    rule on_heartbeatPeerInNeed{
        select when gossip heartbeat
        pre{
            target = selectPeer().klog("target")
            num = random:integer(10).klog("random num:") // between 0 and 10
        }
        if num < 7 then noop() //70% of events will be rumor, 30% seen events
        fired{ 
            raise gossip event "rumorNeeded" attributes{"target":target}
        }
        else {
            raise gossip event "seenNeeded" attributes{"target":target}
        }
    }

    rule seenNeeded{
        select when gossip seenNeeded
        pre{
            target = selectPeer().klog("target:")
            msg = (ent:state{ent:picoID} || ent:knownPicos.map(function(val, key) {0})).klog("seen message:")
        }
        event:send ({ 
            "eci": ent:knownPicos{target}, 
            "eid": "seen message", // can be anything, used for correlation
            "domain": "gossip", "type": "seen",
            "attrs": {
              "seenMsg" : msg,
              "povID" : ent:picoID,
              "violationCount":ent:violationCount
            }
          }.klog("sending seen event:"))
    }

    // includes filtering by is peer needs something from us
    rule rumorNeeded{
        select when gossip rumorNeeded
        pre{
            target = event:attrs{"target"}.klog("target")
            _index = (ent:state{[target, ent:picoID]} + 1 ).klog("next temp index to send:" ) 
            msg = {
                "MessageID": ent:picoID + ":" + _index ,
                "SensorID": ent:picoID,
                "Temperature": ent:allTemps{ent:picoID}[_index], //TODO is this sending bad info and then iterating state to be too high
                "Timestamp": time:now()
            }.klog("rumor msg")
        }
        if msg{"Temperature"} != null && peerIsInNeed(target) then
            event:send({ 
                "eci": ent:knownPicos{target}, 
                "eid": "rumor message", // can be anything, used for correlation
                "domain": "gossip", "type": "rumor",
                "attrs": {
                    "rumorMsg" : msg,
                    "violationStatus":ent:violationStatus
                }
            })
    }
    
    //this rule assumes the rumor is sent and updates state accordingly
    rule updateStateWhenSendingRumor{
        select when gossip rumorNeeded
        pre{
            target = event:attrs{"target"}
            _index = ent:state{[target, ent:picoID]}
            Temperature = ent:allTemps{ent:picoID}[_index] 
        }
        if Temperature != null then noop()
        fired{
            ent:state{[target, ent:picoID]} := ent:state{[target,ent:picoID]} + 1
        }
    }

    rule updatePeriod{
        select when gossip newPeriod
        always{
            ent:period := event:attrs{"newPeriod"}
            // send_directive({"period":ent:period})
        }
    }

    rule start_heartbeat{
        select when gossip start_heartbeat
        pre{
            cron_string = "*/" + ent:period + "  *  * * * *".klog("CRON string: ")
        }
        always{
            schedule gossip event "heartbeat" 
                    repeat cron_string 
        }
    }

    rule stop_heartbeat{
        select when gossip stop_heartbeat
        foreach scheduled_events() setting (event)
        pre{
            _domain = event{"event"}{"domain"}.klog("domain:")
            name = event{"event"}{"name"}.klog("name:")
            id =  event{"id"}
        }
        if _domain == "gossip" && name == "heartbeat" then
            schedule:remove(id)
    }

    rule update_processing{
        select when gossip new_processing
        pre{
            processing = event:attrs{"processing"}
        }
        always{
            ent:processing := processing
        }
        
    }

    rule updateOwnTemps{
        select when wovyn heartbeat
        pre{
            temp = event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureF"}.klog("tempF:")
            this_pico = ent:picoID
            seqID = ent:seqID
        }

        always{
            ent:allTemps{this_pico} := addNewTemp(this_pico, temp)
            ent:state{[this_pico, this_pico]} := ent:state{[this_pico, this_pico]} + 1 
            ent:seqID := ent:seqID + 1
        }
    }

    rule initPeers{
        select when gossip state_initiated
        foreach subs:established("Tx_role", "node").klog("knownPicos:") setting (peer)
        pre{
            tx =  peer{"Tx"}.klog("Tx")
            picoID = wrangler:picoQuery(tx, "gossip", "picoID").klog("peerID")
        } 
        always{
            raise gossip event "newPeer" attributes {
                "picoID" : picoID,
                "Rx": tx
            }
            raise gossip event "allPeersInitialized" on final
        }
    }

    rule initZeroState{
        select when gossip state_initiated
        foreach subs:established("Tx_role", "node").klog("knownPicos:") setting (peer)
        pre{
            tx =  peer{"Tx"}.klog("Tx")
            picoID = wrangler:picoQuery(tx, "gossip", "picoID").klog("peerID")
        }
        always{
            ent:zeroState{picoID} := 0
            ent:zeroState{ent:picoID} := 0 on final
        }
    }

    rule setupOwnState{
        select when gossip allPeersInitialized
        always{
            ent:state{ent:picoID} := ent:zeroState.klog("zeroState:") 
        }
    }
  
    rule newPeer {
        select when gossip newPeer
        pre {
          picoID = event:attrs{"picoID"}.klog("picoID: ")
          rx = event:attrs{"Rx"}.klog("Rx: ")
        }
        send_directive({"picoID": picoID, "rx": rx})
        always{
          ent:knownPicos{picoID} := rx
          ent:state{picoID} := ent:zeroState 
          ent:state{ent:picoID} := addNewPeerToOwnState(picoID) 
          ent:allTemps{picoID} := []
          raise gossip event "newPeerAdded" 
            attributes {"picoID": picoID}
        }
    }

    rule setup{
        select when wrangler ruleset_installed
        always{
            ent:seqID := 0
            ent:picoID := random:word()
            ent:processing := true
            peerArray = subs:established("Tx_role", "node").klog("knownPicos:")
            ent:knownPicos := {}

            ent:allTemps := {}
            ent:allTemps{picoID()} := []
            
            ent:state := {}
            ent:state{picoID()} := ent:knownPicos.map(function(val, key) {0})
            ent:state_violations := 0
            
            raise gossip event "state_initiated"
            raise gossip event "stop_heartbeat"
            raise gossip event "start_heartbeat"
        }
    }
   
  }