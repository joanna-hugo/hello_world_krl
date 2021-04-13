ruleset gossip{
    meta {
      name "Gossip"
      description "implements heterarchal gossip protocol"
      author "Joanna Hugo"
      use module io.picolabs.wrangler alias wrangler
      use module io.picolabs.subscription alias subs

      shares state, snapshot, picoID, update_period, scheduled_events, selectPeer
      provides picoID, scheduled_events, addNewTemp
    }
  
    global{
        period = 20

        state = function(){
            ent:state
        }

        snapshot = function(){
            {
                "state" :   ent:state,
                "seqID" :   ent:seqID,
                "picoID":   ent:picoID,
                "processing": ent:processing,
                "peers":    ent:knownPicos,
                "heartbeat period" : period,
                "allTemps": ent:allTemps
            }
        }

        picoID = function(){
            ent:picoID
        }

        update_period = function(newPeriod){
            period = newPeriod
            period
        }

        scheduled_events = function(){
            schedule:list()
        }

        selectPeer = function(){
            we_know = ent:state{[ent:picoID, ent:picoID]}.klog("number of events we know:")

            temp = ent:state.map(function(val, key) { val{key} }).klog("peers know:")
            diff = temp.filter(function(val, key) {val < we_know}).klog("difference between this and other nodes:")
            _index =  random:integer (diff.length()-1).klog("random index:")

            diff.keys()[_index]  || false 
        }

        addNewTemp = function(picoID, seqID, temp){
            log = ent:allTemps.klog("all temps:")
            logger = picoID.klog("picoID INSIDE func:")
            myTemps = ent:allTemps{picoID}.klog("temps:")
            myTemps.put(seqID, temp).klog("updated temps:")
        }

        updateLastSeen = function(sensorID, msg){
            currentSeen = ent:state{sensorID}
            currentSeen.put("lastSeen", msg)
        }

        sendSeenMessage = defaction(targetID){
            msg = (ent:state{ent:picoID} || ent:knownPicos.map(function(val, key) {0})).klog("seen message:")
            event:send ({ 
                "eci": ent:knownPicos{targetID}, 
                "eid": "seen message", // can be anything, used for correlation
                "domain": "gossip", "type": "seen",
                "attrs": {
                  "seenMsg" : msg,
                  "povID" : ent:picoID
                }
              }.klog("sending seen event:"))
        }

        sendRumorMessage = defaction(targetID){
            templ = ent:allTemps{ent:picoID}.klog("all temps for this pico:")
            _index = (ent:state{[targetID, ent:picoID]}).klog("next temp to send:" )
            msg = {
                "MessageID": ent:picoID + ":" + _index ,
                "SensorID": ent:picoID,
                "Temperature": ent:allTemps{[ent:picoID, _index]},
                "Timestamp": time:now()
            }.klog("rumor msg")
            event:send ({ 
                "eci": ent:knownPicos{targetID}, 
                "eid": "rumor message", // can be anything, used for correlation
                "domain": "gossip", "type": "rumor",
                "attrs": {
                  "rumorMsg" : msg
                }
              }.klog("sending msg event:"))

        }
        
        getSeqIDFromMsg = function(msg){
            msgID = msg{"MessageID"}.klog("msg in parsing func")
            vals = msgID.split(re#:#)
            log = vals[0].klog("parsed at 0:")
            vals[1].klog("parsed seqID")
        }

        addNewPeerToOwnState = function(picoID){
            currentState = ent:state{ent:picoID}
            newState = currentState.put(picoID, 0)
            newState 
        }
    }

    rule reset{
        select when gossip reset
        always{
            ent:seqID := 0
            ent:processing := true
            peerArray = subs:established("Tx_role", "node").klog("knownPicos:") || {}
            ent:knownPicos := {}

            ent:allTemps := {}
            ent:allTemps{ent:picoID} := {}
            
            ent:state := {}
            ent:state{ent:picoID} := {}
            raise gossip event "state_initiated"
            raise gossip event "stop_heartbeat"
            raise gossip event "start_heartbeat"
        }

    }

    /*
    {
        "MessageID" : "planned:154",
        "SensorID" : "planned",
        "Temperature" : 74.8,
        "Timestamp": "2021-04-10T16:26:00.260Z"
    }
    */

    rule on_rumor{
        select when gossip rumor
        pre{
            msg = event:attrs{"rumorMsg"}.klog("rumor msg:")
            seqID = getSeqIDFromMsg(event:attrs{"rumorMsg"}).klog("returned seqID:")
            picoID = event:attrs{"rumorMsg"}{"SensorID"}.klog("sensorID:") //FROM picoID
            temp =event:attrs{"rumorMsg"}{"Temperature"}.klog("temp:")
            myState = ent:state{ent:picoID}.klog("my state:")
            currentCount = ent:state{[ent:picoID, picoID]}.klog("current count: ")
        }
        if ent:processing && seqID > ent:state{[ent:picoID, picoID]} then noop()
        fired{
            ent:allTemps{picoID} := addNewTemp(picoID, seqID, temp)             // add temp to storage
            ent:state{[ent:picoID, picoID]} := currentCount +1   // iterate state 
        }
    }

    rule on_seen{
        select when gossip:seen
        pre{
            msg = event:attrs{"seenMsg"}.klog("seen msg:")
            picoID = event:attrs{"povID"}
        }
        if ent:processing then noop()
        fired{
            ent:state{picoID} := msg
        }
    }
    
    /*
    ALGORTHYM PSUEDOCODE
    when gossip_heartbeat {
        subscriber = getPeer(state)                   
        m = prepareMessage(state, subscriber)     
        send (subscriber, m)            
        update(state)     
      }
    */
    rule on_heartbeat{
        select when gossip heartbeat
        pre{
            target = selectPeer().klog("target:")
        }
        if ent:processing && target then sample{ 
            //target evals to false if we have no information other nodes need, sample rnadomly chooses 1 function
            sendSeenMessage(target)
            sendRumorMessage(target)
        }
    }

    rule start_heartbeat{
        select when gossip start_heartbeat
        pre{
            cron_string = "*/" + period + "  *  * * * *".klog("CRON string: ")
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
            ent:allTemps{this_pico} := addNewTemp(this_pico, seqID, temp)
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
            ent:state{ent:picoID} := ent:zeroState
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
          ent:state{ent:picoID} := addNewPeerToOwnState()
          ent:allTemps{picoID} := {}
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
            ent:allTemps{picoID()} := {}
            
            ent:state := {}
            ent:state{picoID()} := ent:knownPicos.map(function(val, key) {0})
            raise gossip event "state_initiated"
            raise gossip event "stop_heartbeat"
            raise gossip event "start_heartbeat"
        }
    }
   
  }