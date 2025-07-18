---@class threat_table
---@field public is_tanking boolean
---@field public status integer -- 0, 1, 2, 3
---@field public threat_percent number -- 0 to 100

---@class buff
---@field public buff_name string
---@field public buff_id integer
---@field public count number
---@field public expire_time number
---@field public duration number
---@field public type integer
---@field public caster game_object

---@class loss_of_control_info
---@field public valid boolean
---@field public spell_id integer
---@field public start_time integer
---@field public end_time integer
---@field public duration integer
---@field public type integer
---@field public lockout_school schools_flag

---@class item_slot_info
---@field public object game_object
---@field public slot_id integer

---@class game_object
---Returns whether the game_object is valid.
---@field public is_valid fun(self: game_object): boolean
---Returns whether the game_object is visible.
---@field public is_visible fun(self: game_object): boolean
---Returns the type of the game object.
---@field public get_type fun(self: game_object): number
---Returns the class of the game object.
---@field public get_class fun(self: game_object): number
---Returns the spec_id of the game object.
---@field public get_specialization_id fun(self: game_object): number
---Returns the npc_id of the game object.
---@field public get_npc_id fun(self: game_object): number
---Returns the item_id of the game object.
---@field public get_item_id fun(self: game_object): number
---Returns the level of the game object.
---@field public get_level fun(self: game_object): number
---Returns the faction id of the game object.
---@field public get_faction_id fun(self: game_object): number
---Returns the mark id of the game object.  
--- 0 = No Icon   
--- 1 = Yellow 4-point Star  
--- 2 = Orange Circle  
--- 3 = Purple Diamond  
--- 4 = Green Triangle  
--- 5 = White Crescent Moon  
--- 6 = Blue Square  
--- 7 = Red "X" Cross  
--- 8 = White Skull  
---@field public get_target_marker_index fun(self: game_object): number
---Returns the creature_type id of the game object.  
-- 1 -> Beast
-- 2 -> Dragonkin
-- 3 -> Demon
-- 4 -> Elemental
-- 5 -> Giant
-- 6 -> Undead
-- 7 -> Humanoid
-- 8 -> Critter
-- 9 -> Mechanical
-- 10 -> Not specified
-- 11 -> Totem
-- 12 -> Non-combat Pet
-- 13 -> Gas Cloud
-- 14 -> Wild Pet
-- 15 -> Aberration
---@field public get_creature_type fun(self: game_object): number
---Returns the classification id of the game object.  
--- -1 = unknown  
--- 0 = normal  
--- 1 = elite  
--- 2 = rareelite  
--- 3 = worldboss  
--- 4 = rare  
--- 5 = trivial  
--- 6 = minus  
---@field public get_classification fun(self: game_object): number
---Returns the group role of the game object.  
--- "NONE" / unknown = -1  
--- "TANK" = 0  
--- "HEALER" = 1  
--- "DAMAGER" = 2  
---@field public get_group_role fun(self: game_object): number
---Returns the bounding radius of the game object.
---@field public get_bounding_radius fun(self: game_object): number
---Returns the height of the game object.
---@field public get_height fun(self: game_object): number
---Returns the scale of the game object.
---@field public get_scale fun(self: game_object): number
---Returns the cooldown of the specified item.
---@field public get_item_cooldown fun(self: game_object, item_id: integer): number
---Returns whether the game object is a party member.
---@field public is_party_member fun(self: game_object): boolean
---Returns whether the game object has the specified item.
---@field public has_item fun(self: game_object, item_id: integer): boolean
---Returns whether the game object is dead.
---@field public is_dead fun(self: game_object): boolean
---Returns whether the game object is ghost.
---@field public is_ghost fun(self: game_object): boolean
---Returns whether the game object is feigning death.
---@field public is_feign_death fun(self: game_object): boolean
---Returns whether the game object is a basic object.
---@field public is_basic_object fun(self: game_object): boolean
---Returns whether the game object is a player.
---@field public is_player fun(self: game_object): boolean
---Returns whether the game object is a unit.
---@field public is_unit fun(self: game_object): boolean
---Returns whether the game object is a boss.
---@field public is_boss fun(self: game_object): boolean
---Returns whether the game object is an item.
---@field public is_item fun(self: game_object): boolean
---Returns whether the game object is mounted.
---@field public is_mounted fun(self: game_object): boolean
---Returns whether the game object is outdoors.
---@field public is_outdoors fun(self: game_object): boolean
---Returns whether the game object is indoors.
---@field public is_indoors fun(self: game_object): boolean
---Returns whether the game object is glowing.
---@field public is_glow fun(self: game_object): boolean
---Sets the glowing state of the game object.
---@field public set_glow fun(self: game_object, state: boolean): nil
---Returns whether the game object is in combat.
---@field public is_in_combat fun(self: game_object): boolean
---Returns the position of the game object.
---@field public get_position fun(self: game_object): vec3
---Returns the name of the game object.
---@field public get_name fun(self: game_object): string
---Returns the current health of the game object.
---@field public get_health fun(self: game_object): number
---Returns the maximum health of the game object.
---@field public get_max_health fun(self: game_object): number
---Returns the max health modifier of the game object.
---@field public get_max_health_modifier fun(self: game_object): number
---Returns the current power of the game object for the specified power type.  
--- Note: https://wowpedia.fandom.com/wiki/Enum.PowerType
---@field public get_power fun(self: game_object, power_type: number): number
---Returns the maximum power of the game object for the specified power type.  
--- Note: https://wowpedia.fandom.com/wiki/Enum.PowerType
---@field public get_max_power fun(self: game_object, power_type: number): number
---Returns the experience points (XP) of the game object.
---@field public get_xp fun(self: game_object): number
---Returns the maximum experience points (XP) of the game object.
---@field public get_max_xp fun(self: game_object): number
---Returns the total absorb shield of the game object.
---@field public get_total_shield fun(self: game_object): number
---Returns the total incoming heals of the game object.
---@field public get_incoming_heals fun(self: game_object): number
---Returns the incoming heals of the game object from an specific game_object.
---@field public get_incoming_heals_from fun(self: game_object): number
---Returns whether the game object can attack the specified game object.
---@field public can_attack fun(self: game_object, other_game_object: game_object): boolean
---Returns whether the game object is an enemy with the specified game object.
---@field public is_enemy_with fun(self: game_object, other_game_object: game_object): boolean
---Returns whether the game object is a friend with the specified game object.
---@field public is_friend_with fun(self: game_object, other_game_object: game_object): boolean
---Returns whether the game object is moving.
---@field public is_moving fun(self: game_object): boolean
---Returns whether the game object is dashing.
---@field public is_dashing fun(self: game_object): boolean
---Returns whether the game object is flying.
---@field public is_flying fun(self: game_object): boolean
---Returns the current movement speed of the game object.
---@field public get_movement_speed fun(self: game_object): number
---Returns the maximum movement speed of the game object.
---@field public get_movement_speed_max fun(self: game_object): number
---Returns the maximum swim speed of the game object.
---@field public get_swim_speed_max fun(self: game_object): number
---Returns the maximum flight speed of the game object.
---@field public get_flight_speed_max fun(self: game_object): number
---Returns the glide speed of the game object.
---@field public get_glide_speed fun(self: game_object): number
---Returns the auto attack swing speed of the game object.
---@field public get_attack_speed fun(self: game_object): number
---Returns the rotation of the game object.
---@field public get_rotation fun(self: game_object): number
---Returns the direction of the game object.
---@field public get_direction fun(self: game_object): vec3
---Returns the direction of the game object movement manager.
---@field public get_movement_direction fun(self: game_object): vec3
---Returns whether the game object is a pet.
---@field public is_pet fun(self: game_object): boolean
---Returns whether the game object is a minion (alt pets).
---@field public is_minion fun(self: game_object): boolean
---Returns whether the game object is a bag type item.
---@field public is_item_bag fun(self: game_object): boolean
---Returns the stack count of the item in our bag.
---@field public get_item_stack_count fun(self: game_object): number
---Returns the owner of the game object.
---@field public get_owner fun(self: game_object): game_object
---Returns the pet of the game object.
---@field public get_pet fun(self: game_object): game_object
---Returns the target of the game object.
---@field public get_target fun(self: game_object): game_object
---Returns the target of the active spell being cast by the game object.
---@field public get_active_spell_target fun(self: game_object): game_object
---Returns whether the game object is casting a spell.
---@field public is_casting_spell fun(self: game_object): boolean
---Returns the ID of the active spell being cast by the game object.
---@field public get_active_spell_id fun(self: game_object): number
---Returns the start time of the active spell being cast by the game object.
---@field public get_active_spell_cast_start_time fun(self: game_object): number
---Returns the end time of the active spell being cast by the game object.
---@field public get_active_spell_cast_end_time fun(self: game_object): number
---Returns whether the active spell being cast by the game object can be interrupted.
---@field public is_active_spell_interruptable fun(self: game_object): boolean
---Returns whether the game object is currently channeling a spell.
---@field public is_channelling_spell fun(self: game_object): boolean
---Returns the ID of the active channel spell being cast by the game object.
---@field public get_active_channel_spell_id fun(self: game_object): number
---Returns the start time of the active channel spell being cast by the game object.
---@field public get_active_channel_cast_start_time fun(self: game_object): number
---Returns the end time of the active channel spell being cast by the game object.
---@field public get_active_channel_cast_end_time fun(self: game_object): number
---Returns the threat situation from the game_object to another game_object.
---@field public get_threat_situation fun(self: game_object, obj: game_object): threat_table
---Returns a table containing the auras applied to the game object.
---@field public get_auras fun(self: game_object): table<buff>
---Returns a table containing the buffs applied to the game object.
---@field public get_buffs fun(self: game_object): table<buff>
---Returns a table containing the debuffs applied to the game object.
---@field public get_debuffs fun(self: game_object): table<buff>
---Returns a list of equipped items (item_slot_info) of the game object, the format comes in we call item_slot_info, a table that contains game_object ptr of the item and item_slot.
---@field public get_equipped_items fun(self: game_object): table<item_slot_info>
---Returns a table with the item game_object ptr and the slot_id where the item is on the game object equipped items.
---@field public get_item_at_inventory_slot fun(self: game_object, slot:number): item_slot_info
--- Returns whether the game object can be looted.
---@field public can_be_looted fun(self: game_object): boolean
--- Returns whether the game object can be used.
---@field public can_be_used fun(self: game_object): boolean
--- Returns whether the game object can be skinned.
---@field public can_be_skinned fun(self: game_object): boolean
--- Returns the game object creator.
---@field public get_creator_object fun(self: game_object): game_object
---Returns a table containing the loss of control info for the game object.
---@field public get_loss_of_control_info fun(self: game_object): loss_of_control_info
---Returns a table phase id
---@field public get_unit_phase fun(): number
---Returns whether the item in the specified slot has an enchant.
---@field public item_has_enchant fun(self: game_object): boolean
---Returns the expiration time (in seconds) of the enchant on the item in the specified slot.
---@field public item_enchant_expiration fun(self: game_object): number
---Returns the number of remaining charges of the enchant on the item in the specified slot.
---@field public item_enchant_charges fun(self: game_object): integer
---Returns the enchant ID of the item in the specified slot.
---@field public item_enchant_id fun(self: game_object): integer
---Returns the current spell haste percentage of the game object.  
---A value of 8 means 8% haste.
---@field public get_spell_haste fun(self: game_object): number
---@field public get_empower_stage_duration fun(self: game_object, index:number): number