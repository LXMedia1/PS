
-- Example:
-- ---@type auto_attack_helper
-- local x = require("common/utility/auto_attack_helper")
-- x: -> IntelliSense
-- Warning: Access with ":", not "."

---@class auto_attack_helper
---@field attacks_logs table

---@class auto_attack_helper
---@field public is_spell_auto_attack fun(self: auto_attack_helper, spell_id: number): boolean
---@field public get_next_attack_core_time fun(self: auto_attack_helper, unit: any, weapon_count?: number): number
---@field public get_next_attack_game_time fun(self: auto_attack_helper, unit: any, weapon_count?: number): number
---@field public get_global_value_core_time fun(self: auto_attack_helper): number
---@field public get_global_value_game_time fun(self: auto_attack_helper): number
---@field public get_last_global_core_time fun(self: auto_attack_helper): number
---@field public get_last_global_game_time fun(self: auto_attack_helper): number
---@field public get_next_global_core_time fun(self: auto_attack_helper): number
---@field public get_next_global_game_time fun(self: auto_attack_helper): number
---@field public get_combat_start_core_time fun(self: auto_attack_helper): number
---@field public get_combat_start_game_time fun(self: auto_attack_helper): number
---@field public get_current_combat_core_time fun(self: auto_attack_helper): number
---@field public get_current_combat_game_time fun(self: auto_attack_helper): number
