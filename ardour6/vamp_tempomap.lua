ardour { ["type"] = "EditorAction", name = "Vamp TempoMap" }

function factory () return function ()
     -- prepare undo operation
        Session:begin_reversible_command ("Normalize Tracks")
        local add_undo = false -- keep track if something has changed

    -- get Editor selection
    -- http://manual.ardour.org/lua-scripting/class_reference/#ArdourUI:Editor
    -- http://manual.ardour.org/lua-scripting/class_reference/#ArdourUI:Selection
    local sel = Editor:get_selection ()

    local sample_rate = Session:sample_rate()
    print("Sample Rate = ", sample_rate)

    -- Instantiate the QM BarBeat Tracker
    -- see http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR:LuaAPI:Vamp
    -- http://vamp-plugins.org/plugin-doc/qm-vamp-plugins.html#qm-barbeattracker
    local vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-tempotracker", sample_rate)

    -- prepare table to hold results
    local beats = {}

    -- Get the session tempo map
    local tm = Session:tempo_map()

    -- for each selected region
    -- http://manual.ardour.org/lua-scripting/class_reference/#ArdourUI:RegionSelection
    for r in sel.regions:regionlist ():iter () do
        -- "r" is-a http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR:Region

        -- prepare lua table to hold results for the given region (by name)
        beats[r:name ()] = {}

        -- callback to handle Vamp-Plugin analysis results
        function callback (feats)
            -- "feats" is-a http://manual.ardour.org/lua-scripting/class_reference/#Vamp:Plugin:FeatureSet

            -- get the first output. here: Beats, estimated beat locations & beat-number
            local fl = feats:table()[0]
            -- "fl" is-a http://manual.ardour.org/lua-scripting/class_reference/#Vamp:Plugin:FeatureList
            -- which may be empty or not nil
            if fl then
                -- iterate over returned features
                for f in fl:iter () do
                    -- "f" is-a  http://manual.ardour.org/lua-scripting/class_reference/#Vamp:Plugin:Feature
                    if f.hasTimestamp then
                        local fn = Vamp.RealTime.realTime2Frame (f.timestamp, sample_rate)
                        local rbegin = r:position() + fn
                        table.insert (beats[r:name ()], {pos = rbegin, beat = f.label})
                    end
                end
            end

            return false -- continue, !cancel
        end


        -- run the plugin, analyze the first channel of the audio-region
        vamp:analyze (r:to_readable (), 0, callback)
        -- get remaining features (end of analyis)
        callback (vamp:plugin ():getRemainingFeatures ())
        -- reset the plugin (prepare for next iteration)
        vamp:reset ()
    end

    local last_bpm = 0
    local pls = ARDOUR.TempoSection.PositionLockStyle.AudioTime
    -- print results (for now)
    tempo_count = 0
    for n,o in pairs(beats) do
        print ("Tempo analysis for region:", n)
        for _,t in ipairs(o) do
            local bpm = tonumber(t['beat']:match("[0-9]+[.][0-9]+"))
            local sample = tonumber(t['pos'])
            if  bpm and last_bpm ~= bpm then
                tempo_count = tempo_count + 1
                last_bpm = bpm
		tempo = ARDOUR.Tempo(bpm, 4.0, bpm)
		tm:add_tempo(tempo, 0, sample, pls)
		add_undo = true
		print(sample, bpm)
            end
        end
    end

    if add_undo then
        print("Tempo entries: ", tempo_count)
        -- the 'nil' command here means to use all collected diffs
        Session:commit_reversible_command (nil)
    else
        Session:abort_reversible_command ()
    end


end end
