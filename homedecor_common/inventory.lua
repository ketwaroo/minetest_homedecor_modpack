local S = minetest.get_translator("homedecor_common")

local has_hopper = minetest.get_modpath("hopper")
local has_safe_hopper = has_hopper and
	-- mod from https://github.com/minetest-mods/hopper respects the owner
	(hopper.neighbors or
	-- mod from https://notabug.org/TenPlus1/hopper respects the owner since 20220123
	(hopper.version and hopper.version >= "20220123"))

local default_can_dig = function(pos,player)
	local meta = minetest.get_meta(pos)
	return meta:get_inventory():is_empty("main")
end

-- generate an inventory formspec.
local generate_inventory_formspec = function(w, h)
	local playerInvHeight = 4
	local playerInvWidth = 8
	local isMineclone = minetest.get_modpath("mcl_formspec")
	-- cause inventories to be bigger that actaually defined size but close enough.
	if isMineclone then
		playerInvWidth = 9
	end

	local gridWidth = math.max(playerInvWidth, w)
	local gridHeight = playerInvHeight + h + 1

	local invPadding = (gridWidth - w) / 2
	local playerInvPadding = (gridWidth - playerInvWidth) / 2

	-- again, close enough
	local theFormspec = "size[" .. gridWidth .. "," .. gridHeight .. "]" ..
		"list[context;main;" .. invPadding .. ",0.25;" .. w .. "," .. h .. ";]" ..
		"list[current_player;main;" .. playerInvPadding .. "," .. (0.75 + h) .. ";" .. playerInvWidth .. "," .. playerInvHeight .. ";]"


	-- backgrounds
	if mcl_formspec and mcl_formspec.get_itemslot_bg then
		theFormspec = theFormspec ..
			mcl_formspec.get_itemslot_bg(invPadding, 0.25, w, h) ..
			mcl_formspec.get_itemslot_bg(playerInvPadding, (0.75 + h), playerInvWidth, playerInvHeight)
	end

	-- for moving things.
	-- previously some didn't have those defined. not sure why.
	theFormspec = theFormspec ..
		"listring[context;main]" ..
		"listring[current_player;main]"

	return theFormspec
end

local default_inventory_formspecs = {
	["4"]=generate_inventory_formspec(4,1),

	["6"]=generate_inventory_formspec(6,1),

	["8"]=generate_inventory_formspec(8,1),

	["12"]=generate_inventory_formspec(6,2),

	["16"]=generate_inventory_formspec(8,2),

	["24"]=generate_inventory_formspec(8,3),

	["32"]=generate_inventory_formspec(8,4),

	["50"]=generate_inventory_formspec(10,5),
}

local function get_formspec_by_size(size)
	--TODO heuristic to use the "next best size"
	local formspec = default_inventory_formspecs[tostring(size)]
	return formspec or default_inventory_formspecs
end

-- copied from default/functions.lua
-- For games that do not depend on default.
--
-- NOTICE: This method is not an official part of the API yet.
-- This method may change in future.
--
local can_interact_with_node = function (player, pos)

	-- defer to existing.
	-- may break in furure..?
	if default and default.can_interact_with_node then
		return default.can_interact_with_node(player, pos)
	end

	-- else used copied.
	if player and player:is_player() then
		if minetest.check_player_privs(player, "protection_bypass") then
			return true
		end
	else
		return false
	end

	local meta = minetest.get_meta(pos)
	local owner = meta:get_string("owner")

	if not owner or owner == "" or owner == player:get_player_name() then
		return true
	end

	-- Is player wielding the right key?
	local item = player:get_wielded_item()
	if minetest.get_item_group(item:get_name(), "key") == 1 then
		local key_meta = item:get_meta()

		if key_meta:get_string("secret") == "" then
			local key_oldmeta = item:get_metadata()
			if key_oldmeta == "" or not minetest.parse_json(key_oldmeta) then
				return false
			end

			key_meta:set_string("secret", minetest.parse_json(key_oldmeta).secret)
			item:set_metadata("")
		end

		return meta:get_string("key_lock_secret") == key_meta:get_string("secret")
	end

	return false
end


----
-- handle inventory setting
-- inventory = {
--	size = 16,
--	formspec = …,
--	locked = false,
--	lockable = true,
-- }
--
function homedecor.handle_inventory(name, def, original_def)
	local inventory = def.inventory
	if not inventory then return end
	def.inventory = nil

	if inventory.size then
		local on_construct = def.on_construct
		def.on_construct = function(pos)
			local size = inventory.size
			local meta = minetest.get_meta(pos)
			meta:get_inventory():set_size("main", size)
			meta:set_string("formspec", inventory.formspec or get_formspec_by_size(size))
			if on_construct then on_construct(pos) end
		end
	end

	def.can_dig = def.can_dig or default_can_dig
	def.on_metadata_inventory_move = def.on_metadata_inventory_move or
			function(pos, from_list, from_index, to_list, to_index, count, player)
		minetest.log("action", player:get_player_name().." moves stuff in "..name.." at "..minetest.pos_to_string(pos))
	end
	def.on_metadata_inventory_put = def.on_metadata_inventory_put or function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name().." moves "..stack:get_name()
			.." to "..name.." at "..minetest.pos_to_string(pos))
	end
	def.on_metadata_inventory_take = def.on_metadata_inventory_take or function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name().." takes "..stack:get_name()
			.." from "..name.." at "..minetest.pos_to_string(pos))
	end

	local locked = inventory.locked

	if has_hopper and (not locked or has_safe_hopper) then
		if inventory.size then
			hopper:add_container({
				{"top",  "homedecor:"..name, "main"},
				{"bottom", "homedecor:"..name, "main"},
				{"side", "homedecor:"..name, "main"},
			})
		elseif original_def.is_furnace then
			hopper:add_container({
				{"top", "homedecor:"..name, "dst"},
				{"bottom", "homedecor:"..name, "src"},
				{"side", "homedecor:"..name, "fuel"},
			})
		end
	end

	if locked then
		local after_place_node = def.after_place_node
		def.after_place_node = function(pos, placer)
			local meta = minetest.get_meta(pos)
			local owner = placer:get_player_name() or ""

			meta:set_string("owner", owner)
			meta:set_string("infotext", S("@1 (owned by @2)", def.infotext or def.description, owner))
			return after_place_node and after_place_node(pos, placer)
		end

		local allow_move = def.allow_metadata_inventory_move
		def.allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
			if not can_interact_with_node(player, pos) then
				minetest.log("action", player:get_player_name().." tried to access a "..name.." belonging to "
					..minetest.get_meta(pos):get_string("owner").." at "..minetest.pos_to_string(pos))
				return 0
			end
			return allow_move and allow_move(pos, from_list, from_index, to_list, to_index, count, player) or
					count
		end

		local allow_put = def.allow_metadata_inventory_put
		def.allow_metadata_inventory_put = function(pos, listname, index, stack, player)
			if not can_interact_with_node(player, pos) then
				minetest.log("action", player:get_player_name().." tried to access a "..name.." belonging to"
					..minetest.get_meta(pos):get_string("owner").." at "..minetest.pos_to_string(pos))
				return 0
			end
			return allow_put and allow_put(pos, listname, index, stack, player) or
					stack:get_count()
		end

		local allow_take = def.allow_metadata_inventory_take
		def.allow_metadata_inventory_take = function(pos, listname, index, stack, player)
			if not can_interact_with_node(player, pos) then
				minetest.log("action", player:get_player_name().." tried to access a "..name.." belonging to"
					..minetest.get_meta(pos):get_string("owner").." at ".. minetest.pos_to_string(pos))
				return 0
			end
			return allow_take and allow_take(pos, listname, index, stack, player) or
					stack:get_count()
		end

		local can_dig = def.can_dig or default_can_dig
		def.can_dig = function(pos, player)
			return can_interact_with_node(player, pos) and (can_dig and can_dig(pos, player) == true)
		end

		def.on_key_use = function(pos, player)
			local secret = minetest.get_meta(pos):get_string("key_lock_secret")
			local itemstack = player:get_wielded_item()
			local key_meta = itemstack:get_meta()

			if secret ~= key_meta:get_string("secret") then
				return
			end

			minetest.show_formspec(
				player:get_player_name(),
				name.."_locked",
				minetest.get_meta(pos):get_string("formspec")
			)
		end

		def.on_skeleton_key_use = function(pos, player, newsecret)
			local meta = minetest.get_meta(pos)
			local owner = meta:get_string("owner")
			local playername = player:get_player_name()

			-- verify placer is owner
			if owner ~= playername then
				minetest.record_protection_violation(pos, playername)
				return nil
			end

			local secret = meta:get_string("key_lock_secret")
			if secret == "" then
				secret = newsecret
				meta:set_string("key_lock_secret", secret)
			end

			return secret, meta:get_string("description"), owner
		end
	end

	local lockable = inventory.lockable
	if lockable then
		local locked_def = table.copy(original_def)
		locked_def.description = S("@1 (Locked)", def.description or name)
		locked_def.crafts = nil
		local locked_inventory = locked_def.inventory
		locked_inventory.locked = true
		locked_inventory.lockable = nil -- avoid loops of locked locked stuff

		local locked_name = name .. "_locked"
		homedecor.register(locked_name, locked_def)
		minetest.register_craft({
			type = "shapeless",
			output = "homedecor:" .. locked_name,
			recipe = { "homedecor:" .. name, "basic_materials:padlock" }
		})
	end

end
