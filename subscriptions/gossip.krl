ruleset gossip{
     // file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/subscriptions/gossip.krl
    meta {
      name "Gossip"
      description "implements heterarchal gossip protocol"
      author "Joanna Hugo"
      use module io.picolabs.wrangler alias wrangler
      use module io.picolabs.subscription alias subs

      shares state, snapshot, picoID, update_period, scheduled_events
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

        //TODO fix to pick node with the shortest length of 
        selectPeer = function(){
            // ent:state{}

            size =  (ent:knownPicos.length() - 1).klog("size:")
            _index = random:integer(size).klog("_index:") 
            ent:knownPicos.values()[_index].klog("target:")
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
            msg = ent:state{ent:picoID}{"lastSeen"} || ent:knownPicos.map(function(val, key) {0}).klog("lastSeenMsg:") //TODO fix this
            event:send ({ 
                "eci": targetID, 
                "eid": "seen message", // can be anything, used for correlation
                "domain": "gossip", "type": "seen",
                "attrs": {
                  "seenMsg" : msg,
                  "povID" : ent:picoID
                }
              }.klog("sending seen event:"))
        }

        sendRumorMessage = defaction(targetID){
            msg = {
                "MessageID": ent:picoID + ":" + ent:seqID ,
                "SensorID": ent:picoID,
                "SeqID" : ent:seqID,
                "Temperature": ent:state{ent:picoID}{"latestTemp"}{"Temperature"},
                "Timestamp": ent:state{ent:picoID}{"latestTemp"}{"Timestamp"},
            }
            event:send ({ 
                "eci": targetID, 
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
            newState //ent:state{ent:picoID} := newState //.put(picoID, 0)
        }
    }
    //TODO select peer better
    //TODO send personalized message to peer
    
    //DONE state holds data for ALL nodes
    //DONE start and stop processing
    //DONE reacting to events depends on ent:processing


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
            ent:state{ent:picoID} := {}.klog("reset own state to") //ent:knownPicos.map(function(val, key) {0})
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
            picoID = event:attrs{"rumorMsg"}{"SensorID"}.klog("sensorID:")
            temp =event:attrs{"rumorMsg"}{"Temperature"}.klog("temp:")
        }
        // if seqID > ent:state{picoID}{}
        if ent:processing then noop()
        fired{
            logger = picoID.klog("picoID before func:")
            ent:allTemps{picoID} := addNewTemp(picoID, seqID, temp)
            // ent:state{sensorID}{"lastSeen"}:= msg
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
            ent:state{picoID} := msg //addNewTemp(picoID, msg)
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
            temp = "hello world".klog("made it into the on_heartbeat rule:  ")
            target = selectPeer().klog("target:")
        }
        if ent:processing then sample{
            sendRumorMessage(target)
            sendSeenMessage(target)
        }
    }

    //TODO check why period coming up empty
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

    rule choosePeer{
        select when gossip choosePeer
        // filter to peers that need data I have
        // pick the first one
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
            ent:state{this_pico} :=  { 
                "latestTemp":{
                    "MesageID": this_pico + ":" + ent:seqID,
                    "SensorID": this_pico,
                    "Temperature": temp,
                    "Timestamp": time:now()
                }
            }.klog("updated personal state")
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
            // ent:state.put([picoID, picoID], 0) //{picoID} := {picoID : 0}
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

    /*
    [
        {
            "Rx_role":"node",
            "Tx_role":"node",
            "Id":"cknarxm1j02pvg4slel8gbl8h","
            Tx":"cknarxm1j02pwg4sldc1p9y36",
            "Rx":"cknarxm1u02pzg4sl974d5lsw"
        },
        {
            "Rx_role":"node",
            "Tx_role":"node",
            "Id":"cknas4c86031yg4sl5uuk10v9",
            "Rx":"cknas4c86031zg4sla6i2hwr5",
            "Tx":"cknas4c8f0321g4slehy64cia"
        },
        {
            "Rx_role":"node",
            "Tx_role":"node",
            "Id":"cknas4sk30339g4slaflx5cjm",
            "Rx":"cknas4sk3033ag4sl3mbgd0he",
            "Tx":"cknas4skd033cg4sl77fhcqa1"
        }
    ]
    */
    rule newPeer {
        select when gossip newPeer
        pre {
          picoID = event:attrs{"picoID"}.klog("picoID: ")
          rx = event:attrs{"Rx"}.klog("Rx: ")
        }
        send_directive({"picoID": picoID, "rx": rx})
        always{
          ent:knownPicos{picoID} := rx
          ent:state{picoID} := ent:zeroState //ent:knownPicos.map(function(val, key) {0})
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