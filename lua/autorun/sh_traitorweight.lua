----// Traitor Weighting //----
-- Author: Exho
-- Version: 6/9/15

tWeight = {}

--// Extra chances for each usergroup
tWeight.usergroupChances = {
	-- Make sure these names are all lowercase even if your usergroup has mixed letter casings
	-- How its calculated:
		-- The chance is calculated based on player count, 50 means that user group gets (playerCount/2) more chances to be a traitor
		-- So if you have 4 players online and 1 superadmin, that superadmin will have 3 chances to be a traitor as opposed to everyone else's 1
		-- If the superadmin usergroup has 200 and there is 4 players, that superadmin will have 9 chances (1 normal and 8 extra)
	["superadmin"] = 200,
	
	["yourusergroup"] = 15,
}

if SERVER then
	math.randomseed( os.time() )

	util.AddNetworkString( "TTT_networkWeights" ) 

	local plymeta = FindMetaTable( "Player" )

	--// Returns the player's chance of being a traitor (if weighted)
	function plymeta:getTraitorChance()
		local chance = tWeight.usergroupChances[self:GetUserGroup():lower()]
		if chance then
			return chance/100
		end
	end

	--// TTT local function
	local function GetTraitorCount(ply_count)
	   -- get number of traitors: pct of players rounded down
	   local traitor_count = math.floor(ply_count * GetConVar("ttt_traitor_pct"):GetFloat())
	   -- make sure there is at least 1 traitor
	   traitor_count = math.Clamp(traitor_count, 1, GetConVar("ttt_traitor_max"):GetInt())

	   return traitor_count
	end

	--// TTT local function
	local function GetDetectiveCount(ply_count)
	   if ply_count < GetConVar("ttt_detective_min_players"):GetInt() then return 0 end

	   local det_count = math.floor(ply_count * GetConVar("ttt_detective_pct"):GetFloat())
	   -- limit to a max
	   det_count = math.Clamp(det_count, 1, GetConVar("ttt_detective_max"):GetInt())

	   return det_count
	end

	--// TTT's role selection function (overriden)
	function SelectRoles()
	   local choices = {}
	   local prev_roles = {
		[ROLE_INNOCENT] = {},
		[ROLE_TRAITOR] = {},
		[ROLE_DETECTIVE] = {}
	}

	   if not GAMEMODE.LastRole then GAMEMODE.LastRole = {} end

	   for k,v in pairs(player.GetAll()) do
		  -- everyone on the spec team is in specmode
		  if IsValid(v) and (not v:IsSpec()) then
			 -- save previous role and sign up as possible traitor/detective

			 local r = GAMEMODE.LastRole[v:UniqueID()] or v:GetRole() or ROLE_INNOCENT

			 table.insert(prev_roles[r], v)

			 table.insert(choices, v)
		  end

		  v:SetRole(ROLE_INNOCENT)
	   end

	   -- determine how many of each role we want
	   local choice_count = #choices
	   local traitor_count = GetTraitorCount(choice_count)
	   local det_count = GetDetectiveCount(choice_count)

	   if choice_count == 0 then return end
	   
		-- Handle weighted traitor selection
		for _, ply in pairs( player.GetAll() ) do
			local chance = ply:getTraitorChance()
			
			-- They are weighted
			if chance then
				-- Get the amount of times they will be inserted into the pool
				chance = math.ceil(#player.GetAll() * chance)
				
				-- Insert them into the choices table 'i' number of times
				for i = 1, chance do 
					table.insert( choices, ply )
				end
			end
		end

	   -- first select traitors
	   local ts = 0
	   while ts < traitor_count do
		  -- select random index in choices table
		  local pick = math.random(1, #choices)

		  -- the player we consider
		  local pply = choices[pick]

		  -- make this guy traitor if he was not a traitor last time, or if he makes
		  -- a roll
		  if table.HasValue(prev_roles[ROLE_TRAITOR], pply) or math.random(1, 3) == 2 then
			 pply:SetRole(ROLE_TRAITOR)

			 table.remove(choices, pick)
			 ts = ts + 1
		  end
	   end

	   -- now select detectives, explicitly choosing from players who did not get
	   -- traitor, so becoming detective does not mean you lost a chance to be
	   -- traitor
	   local ds = 0
	   local min_karma = GetConVarNumber("ttt_detective_karma_min") or 0
	   while (ds < det_count) and (#choices >= 1) do

		  -- sometimes we need all remaining choices to be detective to fill the
		  -- roles up, this happens more often with a lot of detective-deniers
		  if #choices <= (det_count - ds) then
			 for k, pply in pairs(choices) do
				if IsValid(pply) then
				   pply:SetRole(ROLE_DETECTIVE)
				end
			 end

			 break -- out of while
		  end


		  local pick = math.random(1, #choices)
		  local pply = choices[pick]

		  -- we are less likely to be a detective unless we were innocent last round
		  if (IsValid(pply) and
			  ((pply:GetBaseKarma() > min_karma and
			   table.HasValue(prev_roles[ROLE_INNOCENT], pply)) or
			   math.random(1,3) == 2)) then

			 -- if a player has specified he does not want to be detective, we skip
			 -- him here (he might still get it if we don't have enough
			 -- alternatives)
			 if not pply:GetAvoidDetective() then
				pply:SetRole(ROLE_DETECTIVE)
				ds = ds + 1
			 end

			 table.remove(choices, pick)
		  end
	   end

	   GAMEMODE.LastRole = {}

	   for _, ply in pairs(player.GetAll()) do
		  -- initialize credit count for everyone based on their role
		  ply:SetDefaultCredits()

		  -- store a uid -> role map
		  GAMEMODE.LastRole[ply:UniqueID()] = ply:GetRole()
	   end
	end

	net.Receive( "TTT_networkWeights", function( len, ply )
		local tbl = {}
		
		for _, ply in pairs( player.GetAll() ) do
			local chance = ply:getTraitorChance()
			
			if chance == null then -- Probably a bot
				tbl[ply:Nick()] = 1/#player.GetAll()
			else
				tbl[ply:Nick()] = ply:getTraitorChance()
			end
		end
		
		net.Start( "TTT_networkWeights" )
			net.WriteTable( tbl )
		net.Send( ply )
	end)
end

if CLIENT then
	
	function tWeight.openPanel()
		
		local frame = vgui.Create("DFrame")
		frame:SetSize( 400, 300 )
		frame:SetTitle( "TTT Traitor Weights" )
		frame:MakePopup()
		frame:Center()
		
		tWeight.cached = nil
		
		net.Start( "TTT_networkWeights" )
		net.SendToServer()
		
		if LocalPlayer():Ping() > 80 then
		
			local waitPanel = vgui.Create( "DPanel", frame )
			waitPanel:DockMargin( 30, 30, 30, 30 )
			waitPanel:Dock( FILL )
			waitPanel.Paint = function( self, w, h )
				draw.RoundedBox( 0, 0, 0, w, h, color_white )
			end
			
			local waitLabel = vgui.Create( "DLabel", waitPanel )
			waitLabel:SetTextColor( color_black )
			waitLabel.stage = 1
			waitLabel.nextUpdate = 0
			waitLabel.Think = function( self )
				if CurTime() > self.nextUpdate then
					self:SetText( "Retrieving weights"..string.rep( ".", self.stage ) )
					self:SizeToContents()
					self:SetPos( waitPanel:GetWide()/2 - self:GetWide()/2, waitPanel:GetTall()/2 - self:GetTall()/2 )
					
					self.stage = self.stage + 1
					
					if self.stage > 3 then
						self.stage = 1
					end
					
					self.nextUpdate = CurTime() + 0.2
				end
			end
		end
		
		hook.Add("Think", "tWeight_waitForData", function()
			if tWeight.cached != nil then
				hook.Remove("Think", "tWeight_waitForData")
				
				local playerWeights = vgui.Create( "DListView", frame )
				playerWeights:DockMargin( 10, 10, 10, 10 )
				playerWeights:Dock( FILL )
				playerWeights:AddColumn( "Player" )
				playerWeights:AddColumn( "Weight" )
				
				for nick, chance in pairs( tWeight.cached ) do
					playerWeights:AddLine( nick, chance * #player.GetAll() )
				end
			end
		end)
	end

	concommand.Add( "ttt_weightpanel", tWeight.openPanel )

	net.Receive( "TTT_networkWeights", function( len, ply )
		tWeight.cached = net.ReadTable()
	end)
end

