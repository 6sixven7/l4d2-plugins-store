#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

/* 双奖池初版 0.5.0
 * 玩法参考 L4D2_Lucky_Drawv、Rick Yao 的 L4D2 Tank Draw、
 * 豆瓣酱な的 l4d2_saferoomdoor、Mart 的 l4d_explosion_announcer 1.0.7。
 * Explosion Announcer 来源：https://forums.alliedmods.net/showthread.php?t=328006
 * Tank Draw 来源：https://github.com/rick-yao/L4d2-plugin
 * 独立整合；不需要参考插件的 lib、colors、multicolors 或翻译文件。
 * 普通次数按 Steam2 ID 在内存保存；每次地图开始清空，失败重开保留。
 * 不验证配置名单格式、不去重、不做进服优先身份缓存。
 */
#define VERSION "0.5.0"
#define ENTITY_LIMIT 2049
#define P_COUNT 13
#define N_COUNT 35

public Plugin myinfo = {
    name = "L4D2 Dual Draw", author = "Custom integration; see source references",
    description = "CFG Steam2 priority automatic draw and public manual draw",
    version = VERSION, url = ""
};

char g_PKeys[13][32] = {
    "none",
    "drug",
    "freeze_bomb",
    "time_bomb",
    "tank",
    "witch",
    "moon",
    "heavy",
    "kill",
    "heal",
    "hurt",
    "disarm",
    "jerk"
};
char g_PNames[13][64] = {
    "空奖",
    "个人中毒",
    "冰冻炸弹",
    "定时炸弹",
    "生成Tank",
    "生成Witch",
    "限时个人低重力",
    "个人高重力",
    "个人处死",
    "个人加血",
    "个人扣血",
    "个人缴械",
    "打胶"
};
char g_NKeys[35][40] = {
    "heal_all",
    "clear_common",
    "kill_infected",
    "rifle",
    "rifle_ak47",
    "sniper_military",
    "hunting_rifle",
    "autoshotgun",
    "shotgun_spas",
    "shotgun_chrome",
    "pumpshotgun",
    "rifle_desert",
    "grenade_launcher",
    "smg",
    "smg_silenced",
    "sniper_scout",
    "sniper_awp",
    "first_aid_kit",
    "pain_pills",
    "adrenaline",
    "defibrillator",
    "pistol_magnum",
    "baseball_bat",
    "pipe_bomb",
    "molotov",
    "vomitjar",
    "upgradepack_incendiary",
    "upgradepack_explosive",
    "propanetank",
    "gascan",
    "oxygentank",
    "witch",
    "mob",
    "freeze",
    "jerk"
};
char g_NNames[35][80] = {
    "全体幸存者补满实血",
    "清除普通感染者",
    "处死全部感染者玩家",
    "M16",
    "AK47",
    "军用连狙",
    "猎枪",
    "自动霰弹枪",
    "SPAS",
    "铬合金霰弹枪",
    "泵动霰弹枪",
    "沙漠步枪",
    "榴弹发射器",
    "乌兹",
    "消音冲锋枪",
    "Scout",
    "AWP",
    "医疗包",
    "止痛药",
    "肾上腺素",
    "电击器",
    "马格南",
    "棒球棒",
    "土制炸弹",
    "燃烧瓶",
    "胆汁",
    "燃烧弹升级包",
    "高爆弹升级包",
    "煤气罐",
    "汽油桶",
    "氧气罐",
    "召唤Witch",
    "连续两次尸潮",
    "个人冰冻",
    "打胶"
};

ConVar g_JerkDelay, g_JerkDamage, g_JerkRadius, g_JerkKill, g_JerkBile, g_JerkCooldown;
Handle g_JerkTimer[MAXPLAYERS+1];
float g_JerkEnd[MAXPLAYERS+1], g_LastJerk[MAXPLAYERS+1];
ConVar g_Enable, g_DoorLimit, g_DoorEnable, g_ExplosionEnable, g_GrantPriority, g_GrantChapter;
ConVar g_NormalFreeze, g_PriorityFreeze, g_FreezeCountdown, g_FreezeRadius;
ConVar g_BombCountdown, g_BombRadius, g_BombDamage, g_DrugSeconds;
ConVar g_MoonGravity, g_MoonSeconds, g_HeavyGravity, g_HealMin, g_HealMax, g_HurtMin, g_HurtMax;
ConVar g_DoorCooldown, g_NormalCooldown, g_TestCooldown, g_Debug, g_DoorProgress;
float g_LastDoor[MAXPLAYERS+1], g_LastNormal[MAXPLAYERS+1], g_LastTest[MAXPLAYERS+1];
ConVar g_ExplosionCooldown, g_HudSeconds, g_ExplosionType[8];
ConVar g_PWeight[P_COUNT], g_NWeight[N_COUNT];
ArrayList g_PriorityIDs, g_HudQueue, g_ConfigVars;
StringMap g_Credits, g_Claimed, g_Doors;
bool g_ConfigReady, g_ChapterClosing;
Handle g_HudTimer;
Handle g_FreezeTimer[MAXPLAYERS+1], g_GravityTimer[MAXPLAYERS+1], g_DrugTimer[MAXPLAYERS+1];
Handle g_TimeBomb[MAXPLAYERS+1], g_FreezeBomb[MAXPLAYERS+1];
MoveType g_OldMove[MAXPLAYERS+1];
float g_OldGravity[MAXPLAYERS+1], g_DrugUntil[MAXPLAYERS+1];
bool g_HasGravity[MAXPLAYERS+1];
int g_TimeTicks[MAXPLAYERS+1], g_FreezeTicks[MAXPLAYERS+1];
float g_LastExplosion[MAXPLAYERS+1][8];
int g_EntityType[ENTITY_LIMIT], g_LastAttacker[ENTITY_LIMIT];
bool g_EntityConsumed[ENTITY_LIMIT];
char g_Models[8][96] = {
    "models/props_junk/gascan001a.mdl", "models/props_industrial/barrel_fuel.mdl",
    "models/props_junk/propanecanister001a.mdl", "models/props_equipment/oxygentank01.mdl",
    "models/props_unique/wooden_barricade_gascans.mdl", "models/props_equipment/gas_pump_nodebris.mdl",
    "models/props_junk/explosive_box001.mdl", "models/props_c17/oildrum001_explosive.mdl"
};
char g_ExplosionKeys[8][32] = {"gascan", "fuelbarrel", "propane", "oxygen", "barricade", "gaspump", "fireworks", "oildrum"};
char g_ExplosionNames[8][48] = {"引燃汽油桶", "打爆白色大油桶", "打爆煤气罐", "打爆氧气瓶", "引燃路障油桶", "打爆汽油泵", "点燃烟花盒", "打爆爆炸大油桶"};

ConVar CV(const char[] key, const char[] value, const char[] description, float min = 0.0, float max = 1000000.0)
{
    ConVar cvar = CreateConVar(key, value, description, FCVAR_NONE, true, min, true, max);
    g_ConfigVars.Push(view_as<int>(cvar));
    return cvar;
}

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_Left4Dead2) SetFailState("Only Left 4 Dead 2 is supported.");
    g_ConfigVars = new ArrayList();
    g_PriorityIDs = new ArrayList(ByteCountToCells(64));
    g_HudQueue = new ArrayList(ByteCountToCells(256));
    g_Credits = new StringMap(); g_Claimed = new StringMap(); g_Doors = new StringMap();
    g_Enable = CV("draw_enable", "1", "总开关 0=关闭 1=开启", 0.0, 1.0);
    g_Enable.AddChangeHook(EnableChanged);
    g_DoorEnable = CV("draw_door_enable", "1", "优先玩家开关安全门触发开关", 0.0, 1.0);
    g_ExplosionEnable = CV("draw_explosion_enable", "1", "优先玩家引燃/引爆触发开关", 0.0, 1.0);
    g_DoorLimit = CV("draw_door_limit", "5", "开门与关门分别累计，分别超过此次数抽奖，仅清对应计数", 0.0);
    g_GrantPriority = CV("draw_normal_grant_on_priority", "1", "每次优先抽奖给每位在线真人增加普通次数");
    g_GrantChapter = CV("draw_normal_grant_on_chapter", "3", "每章节每位真人初始普通次数，中途首次加入补领一次");
    g_NormalFreeze = CV("draw_normal_freeze_duration", "50", "普通个人冰冻秒数", 0.1, 3600.0);
    g_PriorityFreeze = CV("draw_priority_freeze_duration", "15", "优先冰冻炸弹造成的冰冻秒数", 0.1, 3600.0);
    g_FreezeCountdown = CV("draw_priority_freeze_bomb_countdown", "8", "优先冰冻炸弹引爆倒计时秒数", 1.0, 3600.0);
    g_FreezeRadius = CV("draw_priority_freeze_bomb_radius", "500", "冰冻炸弹半径", 1.0, 10000.0);
    g_BombCountdown = CV("draw_priority_time_bomb_countdown", "8", "定时炸弹倒计时秒数", 1.0, 3600.0);
    g_BombRadius = CV("draw_priority_time_bomb_radius", "500", "定时炸弹半径", 1.0, 10000.0);
    g_BombDamage = CV("draw_priority_time_bomb_damage", "200", "定时炸弹中心伤害，距离越远越低");
    g_DrugSeconds = CV("draw_priority_drug_duration", "30", "个人中毒持续秒数", 0.1, 3600.0);
    g_MoonGravity = CV("draw_priority_moon_gravity", "0.1", "个人低重力倍率", 0.01, 8.0);
    g_MoonSeconds = CV("draw_priority_moon_duration", "180", "个人低重力秒数", 0.1, 3600.0);
    g_HeavyGravity = CV("draw_priority_heavy_gravity", "3", "个人高重力倍率，死亡或回合结束解除", 0.01, 8.0);
    g_HealMin = CV("draw_priority_heal_min", "200", "加血最小值");
    g_HealMax = CV("draw_priority_heal_max", "500", "加血最大值");
    g_HurtMin = CV("draw_priority_hurt_min", "200", "扣血最小值");
    g_HurtMax = CV("draw_priority_hurt_max", "500", "扣血最大值");
    g_ExplosionCooldown = CV("draw_explosion_cooldown", "0", "同一玩家同一物品类型触发间隔秒数，0=关闭", 0.0, 3600.0);
    g_HudSeconds = CV("draw_hud_seconds", "0", "HUD展示排队间隔，0立即展示不排队；不限制抽奖，支持小数秒", 0.0, 30.0);
    g_DoorCooldown = CV("draw_door_cooldown", "0", "每人玩门抽奖冷却秒数，0无冷却，支持小数", 0.0, 3600.0);
    g_NormalCooldown = CV("draw_normal_cooldown", "0", "每人普通抽奖冷却秒数，0无冷却，支持小数", 0.0, 3600.0);
    g_TestCooldown = CV("draw_test_cooldown", "0", "每人drawpro测试冷却秒数，0无冷却，支持小数", 0.0, 3600.0);
    g_Debug = CV("draw_debug", "0", "触发诊断输出服务器日志，0关闭1开启", 0.0, 1.0);
    g_DoorProgress = CV("draw_door_progress", "1", "向本人提示玩门计数及冷却原因", 0.0, 1.0);
    g_JerkDelay = CV("draw_jerk_countdown", "5", "打胶倒计时秒数，两奖池共用，支持小数", 0.1, 3600.0);
    g_JerkDamage = CV("draw_jerk_damage", "20", "打胶完成本人扣除实血，0不扣；不足时死亡");
    g_JerkRadius = CV("draw_jerk_radius", "500", "打胶范围半径，生还者喷吐与清除感染者均用此范围", 0.0, 10000.0);
    g_JerkKill = CV("draw_jerk_kill_infected", "1", "是否清除范围内普感、特感、Witch、Tank，0否1是", 0.0, 1.0);
    g_JerkBile = CV("draw_jerk_bile_enable", "1", "是否给范围内生还者Bo​​omer喷吐效果，包含本人和BOT", 0.0, 1.0);
    g_JerkCooldown = CV("draw_jerk_test_cooldown", "0", "游客jerk off测试冷却秒数，0无冷却，支持小数", 0.0, 3600.0);
    char key[128], desc[160];
    for (int i = 0; i < P_COUNT; i++)
    {
        Format(key, sizeof(key), "draw_priority_weight_%s", g_PKeys[i]);
        Format(desc, sizeof(desc), "优先奖池：%s，整数权重，0=不参与", g_PNames[i]);
        g_PWeight[i] = CV(key, "10", desc);
    }
    for (int i = 0; i < N_COUNT; i++)
    {
        Format(key, sizeof(key), "draw_normal_weight_%s", g_NKeys[i]);
        Format(desc, sizeof(desc), "普通奖池：%s，整数权重，0=不参与", g_NNames[i]);
        g_NWeight[i] = CV(key, "10", desc);
    }
    for (int i = 0; i < 8; i++)
    {
        Format(key, sizeof(key), "draw_trigger_%s", g_ExplosionKeys[i]);
        Format(desc, sizeof(desc), "%s提示与优先抽奖开关", g_ExplosionNames[i]);
        g_ExplosionType[i] = CV(key, "1", desc, 0.0, 1.0);
    }
    RegServerCmd("draw_priority_clear", CmdPriorityClear, "清空优先名单，仅服务器控制台");
    RegServerCmd("draw_priority_add", CmdPriorityAdd, "添加一个固定格式Steam2 ID，仅服务器控制台");
    RegConsoleCmd("sm_draw", CmdDraw, "查看次数或手动普通抽奖");
    RegConsoleCmd("sm_ldw", CmdDraw, "普通抽奖菜单别名");
    RegConsoleCmd("sm_drawpro", CmdDrawPro, "游客可用的优先抽奖测试，跳过名单，实际结算奖品及全员赠送");
    RegConsoleCmd("sm_jerk", CmdJerk, "游客测试：聊天输入 !jerk off，启动打胶倒计时");
    HookEvent("door_open", EventDoor); HookEvent("door_close", EventDoor);
    HookEvent("break_prop", EventBreakProp);
    HookEvent("round_start", EventRoundStart);
    HookEvent("mission_lost", EventRoundEnd); HookEvent("round_end", EventRoundEnd);
    HookEvent("map_transition", EventTransition); HookEvent("finale_win", EventTransition);
    HookEvent("player_death", EventDeath);
    HookEvent("player_team", EventDeath); // personal effects end on team changes; credits remain
    // Create only missing files; each contains only its own category.
    EnsureConfig("draw_settings", 0);
    EnsureConfig("draw_priority", 1);
    EnsureConfig("draw_normal", 2);
    EnsureConfig("draw_priority_memberlist", 3);
    // SourceMod calls OnConfigsExecuted only after these queued files execute,
    // including late plugin loads. Do not grant chapter credits before that.
    AutoExecConfig(false, "draw_settings");
    AutoExecConfig(false, "draw_priority");
    AutoExecConfig(false, "draw_normal");
    AutoExecConfig(false, "draw_priority_memberlist");
}

bool Human(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}
bool AliveSurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client);
}
bool Standing(int client)
{
    return AliveSurvivor(client) && !GetEntProp(client, Prop_Send, "m_isIncapacitated") && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}
bool Auth(int client, char[] id, int size)
{
    return Human(client) && GetClientAuthId(client, AuthId_Steam2, id, size);
}
bool Priority(int client)
{
    char id[64], entry[64];
    if (!Auth(client, id, sizeof(id))) return false;
    for (int i = 0; i < g_PriorityIDs.Length; i++)
    {
        g_PriorityIDs.GetString(i, entry, sizeof(entry));
        if (StrEqual(id, entry)) return true;
    }
    return false;
}
public Action CmdPriorityClear(int args)
{
    g_PriorityIDs.Clear();
    return Plugin_Handled;
}
public Action CmdPriorityAdd(int args)
{
    if (args != 1) { PrintToServer("Usage: draw_priority_add STEAM_x:x:xxx"); return Plugin_Handled; }
    char id[64]; GetCmdArg(1, id, sizeof(id)); g_PriorityIDs.PushString(id);
    return Plugin_Handled;
}
int Balance(const char[] id)
{
    int value; g_Credits.GetValue(id, value); return value;
}
void AddCredit(const char[] id, int amount)
{
    int old = Balance(id);
    // Saturation prevents integer overflow without imposing a gameplay cap.
    g_Credits.SetValue(id, amount > 2147483647 - old ? 2147483647 : old + amount);
}
void ClaimChapter(int client)
{
    if (!g_ConfigReady || g_ChapterClosing || !g_Enable.BoolValue) return;
    char id[64]; if (!Auth(client, id, sizeof(id))) return;
    int claimed;
    if (g_Claimed.GetValue(id, claimed)) return;
    g_Claimed.SetValue(id, 1);
    AddCredit(id, g_GrantChapter.IntValue);
    PrintToChat(client, "\x04[抽奖]\x01 本章初始次数 +%d，当前 %d 次。输入 !ldw 抽奖。", g_GrantChapter.IntValue, Balance(id));
}
public void OnClientPostAdminCheck(int client) { ClaimChapter(client); }
public void OnConfigsExecuted()
{
    g_ConfigReady = true;
    int priorityTotal, normalTotal;
    for (int i = 0; i < P_COUNT; i++) priorityTotal += g_PWeight[i].IntValue;
    for (int i = 0; i < N_COUNT; i++) normalTotal += g_NWeight[i].IntValue;
    PrintToServer("[Dual Draw] CFG loaded: enable=%d, chapter=%d, grant=%d, priority total=%d, normal total=%d, IDs=%d",
        g_Enable.IntValue, g_GrantChapter.IntValue, g_GrantPriority.IntValue, priorityTotal, normalTotal, g_PriorityIDs.Length);
    for (int i = 1; i <= MaxClients; i++) ClaimChapter(i);
    ScanProps();
}
public void OnMapStart()
{
    ResetEffects(); ClearHud();
    g_Credits.Clear(); g_Claimed.Clear(); g_Doors.Clear();
    g_ConfigReady = false; g_ChapterClosing = false;
    for (int e = 0; e < ENTITY_LIMIT; e++) { g_EntityType[e] = 0; g_LastAttacker[e] = 0; g_EntityConsumed[e] = false; }
    for (int i = 1; i <= MaxClients; i++)
        g_LastJerk[i] = g_LastDoor[i] = g_LastNormal[i] = g_LastTest[i] = -99999.0;
    for (int i = 1; i <= MaxClients; i++)
        for (int t = 0; t < 8; t++) g_LastExplosion[i][t] = -99999.0;
}
public void OnMapEnd() { ResetEffects(); ClearHud(); g_ConfigReady = false; }
public void OnPluginEnd() { ResetEffects(); ClearHud(); }
public void OnClientDisconnect(int client)
{
    ClearClientEffects(client);
    g_LastJerk[client] = g_LastDoor[client] = g_LastNormal[client] = g_LastTest[client] = -99999.0;
    for (int t = 0; t < 8; t++) g_LastExplosion[client][t] = -99999.0;
    // SteamID balances and claim flags intentionally survive disconnects.
}
public void EventRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetEffects();
    g_ChapterClosing = false;
    for (int i = 1; i <= MaxClients; i++) ClaimChapter(i);
    ScanProps();
}
public void EventRoundEnd(Event event, const char[] name, bool dontBroadcast) { ResetEffects(); }
public void EventTransition(Event event, const char[] name, bool dontBroadcast)
{
    g_ChapterClosing = true;
    ResetEffects(); ClearHud();
    g_Credits.Clear(); g_Claimed.Clear(); g_Doors.Clear();
}
public void EventDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) ClearClientEffects(client);
}
public void EnableChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue) { ResetEffects(); ClearHud(); }
    else for (int i = 1; i <= MaxClients; i++) ClaimChapter(i);
}

public Action CmdDraw(int client, int args)
{
    if (!Human(client)) return Plugin_Handled;
    ClaimChapter(client);
    char id[64]; if (!Auth(client, id, sizeof(id))) return Plugin_Handled;
    Menu menu = new Menu(DrawMenu);
    menu.SetTitle("普通抽奖\n剩余次数：%d", Balance(id));
    menu.AddItem("draw", "抽一次"); menu.Display(client, 30);
    return Plugin_Handled;
}
public int DrawMenu(Menu menu, MenuAction action, int client, int selection)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_Select)
    {
        if (!Human(client)) return 0;
        if (!g_Enable.BoolValue || g_ChapterClosing) { PrintToChat(client, "[抽奖] 当前不可抽奖。"); return 0; }
        if (!Standing(client)) { PrintToChat(client, "[抽奖] 次数保留，请在存活、站立的幸存者状态抽取。"); return 0; }
        char id[64]; if (!Auth(client, id, sizeof(id))) return 0;
        int count = Balance(id);
        if (count <= 0) { PrintToChat(client, "[抽奖] 没有普通抽奖次数。"); return 0; }
        if (Cooling(client, g_NormalCooldown, g_LastNormal[client], "普通抽奖", true)) return 0;
        int prize = Roll(false);
        if (prize < 0) { PrintToChat(client, "[抽奖] 普通奖池权重全部为0，未扣次数。"); return 0; }
        g_Credits.SetValue(id, count - 1);
        bool success = ApplyNormal(client, prize);
        if (!success) { AddCredit(id, 1); PrintToChat(client, "[抽奖] 奖项执行失败，已退还次数。"); }
        else { g_LastNormal[client] = GetGameTime(); PrintToChatAll("\x04[普通抽奖]\x03 %N\x01 抽到：%s", client, g_NNames[prize]); }
    }
    return 0;
}
int Roll(bool priority)
{
    int total, count = priority ? P_COUNT : N_COUNT;
    for (int i = 0; i < count; i++) total += priority ? g_PWeight[i].IntValue : g_NWeight[i].IntValue;
    if (total <= 0) return -1;
    int pick = GetRandomInt(1, total), cumulative;
    for (int i = 0; i < count; i++)
    {
        cumulative += priority ? g_PWeight[i].IntValue : g_NWeight[i].IntValue;
        if (pick <= cumulative) return i;
    }
    return -1;
}
public Action CmdDrawPro(int client, int args)
{
    if (!Human(client)) { ReplyToCommand(client, "[抽奖] 请由游戏内真人玩家执行 !drawpro。"); return Plugin_Handled; }
    if (!g_ConfigReady || !g_Enable.BoolValue || g_ChapterClosing)
    {
        ReplyToCommand(client, "[抽奖] 配置未就绪、插件关闭或章节已结束，无法测试。");
        return Plugin_Handled;
    }
    if (!Standing(client))
    {
        ReplyToCommand(client, "[抽奖] 请在存活、站立的幸存者状态测试优先奖池。");
        return Plugin_Handled;
    }
    if (RollTotal(true) <= 0)
    {
        ReplyToCommand(client, "[抽奖] 优先奖池总权重为0，未抽奖、未发赠送次数。");
        return Plugin_Handled;
    }
    if (Cooling(client, g_TestCooldown, g_LastTest[client], "测试抽奖", true)) return Plugin_Handled;
    if (PriorityDraw(client, "使用 !drawpro 测试", true)) g_LastTest[client] = GetGameTime();
    return Plugin_Handled;
}
int RollTotal(bool priority)
{
    int total, count = priority ? P_COUNT : N_COUNT;
    for (int i = 0; i < count; i++) total += priority ? g_PWeight[i].IntValue : g_NWeight[i].IntValue;
    return total;
}
bool PriorityDraw(int client, const char[] reason, bool test = false)
{
    if (!g_Enable.BoolValue || !g_ConfigReady || g_ChapterClosing || !Human(client) || (!test && !Priority(client))) return false;
    int prize = Roll(true); if (prize < 0) return false;
    // Grant before applying a lethal result; all currently connected humans get the grant.
    int amount = g_GrantPriority.IntValue;
    for (int i = 1; i <= MaxClients; i++)
    {
        ClaimChapter(i);
        char id[64]; if (!Auth(i, id, sizeof(id))) continue;
        AddCredit(id, amount);
        PrintToChat(i, "\x04[抽奖]\x01 优先抽奖赠送普通次数 +%d，当前 %d 次。", amount, Balance(id));
    }
    char message[256]; Format(message, sizeof(message), "%N：%s\n优先抽奖：%s", client, reason, g_PNames[prize]);
    PrintToChatAll("\x04[优先抽奖]\x03 %N\x01 因%s，抽到：%s", client, reason, g_PNames[prize]);
    QueueHud(message);
    if (!ApplyPriority(client, prize)) PrintToChatAll("[优先抽奖] 本次奖项未生效（角色非站立幸存者，或生成位置/实体受限）。");
    return true;
}
void QueueHud(const char[] message)
{
    if (g_HudSeconds.FloatValue <= 0.0) { PrintHintTextToAll("%s", message); return; }
    if (g_HudTimer == null)
    {
        PrintHintTextToAll("%s", message);
        g_HudTimer = CreateTimer(g_HudSeconds.FloatValue, NextHud);
    }
    else g_HudQueue.PushString(message);
}
public Action NextHud(Handle timer)
{
    g_HudTimer = null;
    if (g_HudQueue.Length > 0)
    {
        char message[256]; g_HudQueue.GetString(0, message, sizeof(message)); g_HudQueue.Erase(0);
        QueueHud(message);
    }
    return Plugin_Stop;
}
void ClearHud() { delete g_HudTimer; if (g_HudQueue != null) g_HudQueue.Clear(); }

// Ported from saferoomdoor: checkpoint door_open + door_close, survivor filter,
// independent direction counters, strict > threshold. No death/kick/ban or hidden movement throttle.
public void EventDoor(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Human(client)) return;
    if (g_Debug.BoolValue) LogMessage("[Door] client=%N event=%s checkpoint=%d team=%d ready=%d closing=%d priority=%d", client, name, event.GetBool("checkpoint"), GetClientTeam(client), g_ConfigReady, g_ChapterClosing, Priority(client));
    if (!g_Enable.BoolValue || !g_DoorEnable.BoolValue || !g_ConfigReady || g_ChapterClosing) return;
    if (GetClientTeam(client) != 2 || !event.GetBool("checkpoint") || !Priority(client)) return;
    char id[64], key[80]; if (!Auth(client, id, sizeof(id))) return;
    bool opening = StrEqual(name, "door_open");
    Format(key, sizeof(key), "%s:%s", id, opening ? "open" : "close");
    int count; g_Doors.GetValue(key, count);
    if (count <= g_DoorLimit.IntValue) count++;
    if (g_DoorProgress.BoolValue) PrintToChat(client, "[玩门抽奖] %s累计 %d 次，超过 %d 次抽奖（开关分别计数）。", opening ? "开门" : "关门", count, g_DoorLimit.IntValue);
    if (count > g_DoorLimit.IntValue)
    {
        if (!Cooling(client, g_DoorCooldown, g_LastDoor[client], "玩门抽奖", g_DoorProgress.BoolValue))
        {
            if (PriorityDraw(client, opening ? "开安全门超过次数" : "关安全门超过次数")) { count = 0; g_LastDoor[client] = GetGameTime(); }
            else if (g_DoorProgress.BoolValue) PrintToChat(client, "[玩门抽奖] 本次未抽取，请检查奖池权重和开关；计数保留。");
        }
    }
    g_Doors.SetValue(key, count);
}

// Explosion recognition follows the supplied announcer's model/attacker attribution.
// It is self-contained: no parsing chat text and no dependency on another plugin's CVars.
bool PropIndex(int entity) { return entity > MaxClients && entity < ENTITY_LIMIT; }
public void OnEntityCreated(int entity, const char[] classname)
{
    if (!PropIndex(entity)) return;
    g_EntityType[entity] = 0; g_LastAttacker[entity] = 0; g_EntityConsumed[entity] = false;
    if (StrEqual(classname, "weapon_gascan") || StrContains(classname, "prop_") == 0 || StrEqual(classname, "physics_prop"))
        { SDKHook(entity, SDKHook_SpawnPost, PropSpawned); RequestFrame(InspectProp, EntIndexToEntRef(entity)); }
}
public void OnEntityDestroyed(int entity)
{
    // Snapshot remains readable by late break_prop; OnEntityCreated clears reused slots.
}
void ScanProps()
{
    for (int entity = MaxClients + 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
        if (IsValidEntity(entity)) RequestFrame(InspectProp, EntIndexToEntRef(entity));
}
public void InspectProp(any reference)
{
    int entity = EntRefToEntIndex(reference);
    if (!PropIndex(entity) || !IsValidEntity(entity) || g_EntityType[entity] != 0) return;
    char classname[64]; GetEntityClassname(entity, classname, sizeof(classname));
    if (!StrEqual(classname, "weapon_gascan") && StrContains(classname, "prop_") != 0 && !StrEqual(classname, "physics_prop")) return;
    // Also recognize plugin-created visible props; HammerID -1 is not a cooldown.
    int rgba[4]; GetEntityRenderColor(entity, rgba[0], rgba[1], rgba[2], rgba[3]);
    RenderMode mode = GetEntityRenderMode(entity);
    if (mode == RENDER_NONE || (mode == RENDER_TRANSCOLOR && rgba[3] == 0)) return;
    char model[PLATFORM_MAX_PATH]; GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
    for (int type = 0; type < 8; type++)
    {
        if (!StrEqual(model, g_Models[type], false)) continue;
        g_EntityType[entity] = type + 1;
        SDKHook(entity, SDKHook_OnTakeDamage, PropDamage);
        if (StrEqual(classname, "weapon_gascan")) HookSingleEntityOutput(entity, "OnKilled", PropKilled, true);
        break;
    }
}
public Action PropDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (Human(attacker)) g_LastAttacker[victim] = GetClientUserId(attacker);
    return Plugin_Continue;
}
public void PropKilled(const char[] output, int caller, int activator, float delay)
{
    if (!PropIndex(caller)) return;
    if (Human(activator)) g_LastAttacker[caller] = GetClientUserId(activator);
    ExplosionNotice(caller, GetClientOfUserId(g_LastAttacker[caller]));
}
public void EventBreakProp(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("entindex"); if (!PropIndex(entity)) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Human(client)) client = GetClientOfUserId(g_LastAttacker[entity]);
    ExplosionNotice(entity, client);
}
void ExplosionNotice(int entity, int client)
{
    int type = g_EntityType[entity] - 1;
    if (type < 0 || g_EntityConsumed[entity] || !Human(client)) return;
    g_EntityConsumed[entity] = true; // one object, one event even when OnKilled + break_prop both fire
    if (g_Debug.BoolValue) LogMessage("[Explosion] client=%N entity=%d type=%d priority=%d", client, entity, type, Priority(client));
    if (!g_Enable.BoolValue || !g_ExplosionEnable.BoolValue || !g_ExplosionType[type].BoolValue || !g_ConfigReady || g_ChapterClosing) return;
    PrintToChatAll("\x04[提示]\x03 %N\x01 %s！", client, g_ExplosionNames[type]);
    if (!Priority(client)) return;
    if (Cooling(client, g_ExplosionCooldown, g_LastExplosion[client][type], "物品抽奖", true)) return;
    if (PriorityDraw(client, g_ExplosionNames[type])) g_LastExplosion[client][type] = GetGameTime();
}

bool Cheat(int client, const char[] command, const char[] argument)
{
    int flags = GetCommandFlags(command); if (flags == INVALID_FCVAR_FLAGS) return false;
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "%s %s", command, argument);
    SetCommandFlags(command, flags);
    return true;
}
bool SpawnSpecial(int client, bool tank)
{
    float origin[3]; GetClientAbsOrigin(client, origin);
    return (tank ? L4D2_SpawnTank(origin, NULL_VECTOR) : L4D2_SpawnWitch(origin, NULL_VECTOR)) > 0;
}
int RandomRange(ConVar low, ConVar high)
{
    int a = low.IntValue, b = high.IntValue;
    return GetRandomInt(a < b ? a : b, a < b ? b : a);
}
bool ApplyPriority(int client, int prize)
{
    if (prize == 12) return StartJerk(client);
    if (prize != 0 && !Standing(client)) return false;
    switch (prize)
    {
        case 0: return true;
        case 1:
        {
            delete g_DrugTimer[client];
            g_DrugUntil[client] = GetGameTime() + g_DrugSeconds.FloatValue;
            g_DrugTimer[client] = CreateTimer(0.2, DrugTick, GetClientUserId(client), TIMER_REPEAT);
        }
        case 2: { ToggleBomb(client, true); }
        case 3: { ToggleBomb(client, false); }
        case 4: return SpawnSpecial(client, true);
        case 5: return SpawnSpecial(client, false);
        case 6: SetGravityEffect(client, g_MoonGravity.FloatValue, g_MoonSeconds.FloatValue);
        case 7: SetGravityEffect(client, g_HeavyGravity.FloatValue, 0.0);
        case 8: ForcePlayerSuicide(client);
        case 9:
        {
            int hp = GetClientHealth(client), maxhp = GetEntProp(client, Prop_Data, "m_iMaxHealth");
            int value = hp + RandomRange(g_HealMin, g_HealMax);
            if (value > maxhp) value = maxhp;
            if (value < hp) value = hp;
            SetEntityHealth(client, value);
        }
        case 10:
        {
            int hp = GetClientHealth(client) - RandomRange(g_HurtMin, g_HurtMax);
            SetEntityHealth(client, hp < 1 ? 1 : hp);
        }
        case 11:
        {
            for (int slot = 0; slot < 5; slot++)
            {
                int weapon;
                while ((weapon = GetPlayerWeaponSlot(client, slot)) > MaxClients)
                {
                    if (!RemovePlayerItem(client, weapon)) break;
                    RemoveEntity(weapon);
                }
            }
        }
    }
    return true;
}
bool ApplyNormal(int client, int prize)
{
    if (prize == 34) return StartJerk(client);
    if (prize >= 3 && prize <= 30) return Cheat(client, "give", g_NKeys[prize]);
    switch (prize)
    {
        case 0:
        {
            for (int i = 1; i <= MaxClients; i++)
                if (Standing(i)) SetEntityHealth(i, GetEntProp(i, Prop_Data, "m_iMaxHealth"));
        }
        case 1:
        {
            int entity = -1;
            while ((entity = FindEntityByClassname(entity, "infected")) != -1) RemoveEntity(entity);
        }
        case 2:
        {
            for (int i = 1; i <= MaxClients; i++)
                if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i)) ForcePlayerSuicide(i);
        }
        case 31: return SpawnSpecial(client, false);
        case 32: { Cheat(client, "z_spawn", "mob"); return Cheat(client, "z_spawn", "mob"); }
        case 33: Freeze(client, g_NormalFreeze.FloatValue);
    }
    return true;
}

void Freeze(int client, float seconds)
{
    if (!AliveSurvivor(client)) return;
    if (g_FreezeTimer[client] == null) g_OldMove[client] = GetEntityMoveType(client);
    delete g_FreezeTimer[client];
    SetEntityMoveType(client, MOVETYPE_NONE);
    g_FreezeTimer[client] = CreateTimer(seconds, Unfreeze, GetClientUserId(client));
}
public Action Unfreeze(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0)
    {
        g_FreezeTimer[client] = null;
        if (IsPlayerAlive(client) && GetEntityMoveType(client) == MOVETYPE_NONE) SetEntityMoveType(client, g_OldMove[client]);
    }
    return Plugin_Stop;
}
void SetGravityEffect(int client, float gravity, float seconds)
{
    if (!g_HasGravity[client]) { g_OldGravity[client] = GetEntityGravity(client); g_HasGravity[client] = true; }
    delete g_GravityTimer[client]; SetEntityGravity(client, gravity);
    if (seconds > 0.0) g_GravityTimer[client] = CreateTimer(seconds, GravityBack, GetClientUserId(client));
}
public Action GravityBack(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0)
    {
        g_GravityTimer[client] = null;
        if (g_HasGravity[client]) SetEntityGravity(client, g_OldGravity[client]);
        g_HasGravity[client] = false;
    }
    return Plugin_Stop;
}
void ResetRoll(int client)
{
    float angles[3]; GetClientEyeAngles(client, angles); angles[2] = 0.0;
    TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
}
public Action DrugTick(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0) return Plugin_Stop;
    if (!AliveSurvivor(client) || GetGameTime() >= g_DrugUntil[client])
    {
        g_DrugTimer[client] = null; ResetRoll(client); return Plugin_Stop;
    }
    float angles[3]; GetClientEyeAngles(client, angles);
    angles[2] = Sine(GetGameTime() * 4.0) * 20.0;
    TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
    return Plugin_Continue;
}
void ToggleBomb(int client, bool freeze)
{
    if (freeze)
    {
        if (g_FreezeBomb[client] != null) { delete g_FreezeBomb[client]; PrintToChatAll("[抽奖] %N 的冰冻炸弹已取消。", client); return; }
        g_FreezeTicks[client] = g_FreezeCountdown.IntValue;
        g_FreezeBomb[client] = CreateTimer(1.0, FreezeBombTick, GetClientUserId(client), TIMER_REPEAT);
    }
    else
    {
        if (g_TimeBomb[client] != null) { delete g_TimeBomb[client]; PrintToChatAll("[抽奖] %N 的定时炸弹已取消。", client); return; }
        g_TimeTicks[client] = g_BombCountdown.IntValue;
        g_TimeBomb[client] = CreateTimer(1.0, TimeBombTick, GetClientUserId(client), TIMER_REPEAT);
    }
    Cheat(client, "give", "adrenaline");
}
public Action FreezeBombTick(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0) return Plugin_Stop;
    if (!AliveSurvivor(client)) { g_FreezeBomb[client] = null; return Plugin_Stop; }
    g_FreezeTicks[client]--;
    if (g_FreezeTicks[client] > 0)
    {
        PrintToChatAll("[冰冻炸弹] %N：%d 秒后引爆。", client, g_FreezeTicks[client]); return Plugin_Continue;
    }
    g_FreezeBomb[client] = null;
    float origin[3], pos[3]; GetClientAbsOrigin(client, origin);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!AliveSurvivor(i)) continue;
        GetClientAbsOrigin(i, pos);
        if (GetVectorDistance(origin, pos) <= g_FreezeRadius.FloatValue) Freeze(i, g_PriorityFreeze.FloatValue);
    }
    PrintToChatAll("[冰冻炸弹] %N 已引爆！", client);
    return Plugin_Stop;
}
public Action TimeBombTick(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0) return Plugin_Stop;
    if (!AliveSurvivor(client)) { g_TimeBomb[client] = null; return Plugin_Stop; }
    g_TimeTicks[client]--;
    if (g_TimeTicks[client] > 0)
    {
        PrintToChatAll("[定时炸弹] %N：%d 秒后引爆。", client, g_TimeTicks[client]); return Plugin_Continue;
    }
    g_TimeBomb[client] = null; // clear before suicide invokes player_death
    float origin[3], pos[3]; GetClientAbsOrigin(client, origin);
    PrintToChatAll("[定时炸弹] %N 已引爆！", client);
    ForcePlayerSuicide(client);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client || !AliveSurvivor(i)) continue;
        GetClientAbsOrigin(i, pos);
        float distance = GetVectorDistance(origin, pos), radius = g_BombRadius.FloatValue;
        if (distance < radius) SDKHooks_TakeDamage(i, 0, client, float(g_BombDamage.IntValue) * (1.0 - distance / radius), DMG_GENERIC);
    }
    return Plugin_Stop;
}
void ClearClientEffects(int client)
{
    if (IsClientInGame(client))
    {
        if (g_FreezeTimer[client] != null && IsPlayerAlive(client) && GetEntityMoveType(client) == MOVETYPE_NONE)
            SetEntityMoveType(client, g_OldMove[client]);
        if (g_HasGravity[client]) SetEntityGravity(client, g_OldGravity[client]);
        if (g_DrugTimer[client] != null) ResetRoll(client);
    }
    delete g_JerkTimer[client];
    delete g_FreezeTimer[client]; delete g_GravityTimer[client]; delete g_DrugTimer[client];
    delete g_TimeBomb[client]; delete g_FreezeBomb[client];
    g_HasGravity[client] = false;
}
void ResetEffects()
{
    for (int i = 1; i <= MaxClients; i++) ClearClientEffects(i);
}

// kind: 0=settings, 1=priority weights, 2=normal weights, 3=member list.
void EnsureConfig(const char[] filename, int kind)
{
    char path[PLATFORM_MAX_PATH];
    Format(path, sizeof(path), "cfg/sourcemod/%s.cfg", filename);
    if (FileExists(path)) return;
    if (!DirExists("cfg/sourcemod") && !CreateDirectory("cfg/sourcemod", 511))
    {
        SetFailState("Cannot create cfg/sourcemod directory");
        return;
    }
    File file = OpenFile(path, "w");
    if (file == null) { SetFailState("Cannot create %s", path); return; }
    file.WriteLine("// Dual Draw 0.5.0 - missing files are generated once; existing files are preserved.");
    if (kind == 3)
    {
        file.WriteLine("// Server-only list commands, not CVars. Add one Steam2 ID per line.");
        file.WriteLine("draw_priority_clear");
        file.WriteLine("// draw_priority_add \"STEAM_1:0:12345678\"");
        delete file;
        return;
    }
    else if (kind != 0) file.WriteLine("// Integer weights: probability = weight / sum of weights in THIS pool. 0=excluded.");
    char name[128], value[64], description[256];
    for (int i = 0; i < g_ConfigVars.Length; i++)
    {
        ConVar cvar = view_as<ConVar>(g_ConfigVars.Get(i));
        cvar.GetName(name, sizeof(name));
        int category = 0;
        if (StrContains(name, "draw_priority_weight_") == 0) category = 1;
        else if (StrContains(name, "draw_normal_weight_") == 0) category = 2;
        if (category != kind) continue;
        cvar.GetDefault(value, sizeof(value));
        cvar.GetDescription(description, sizeof(description));
        file.WriteLine("// %s", description);
        file.WriteLine("%s \"%s\"", name, value);
        file.WriteLine("");
    }
    delete file;
}

public void PropSpawned(int entity) { RequestFrame(InspectProp, EntIndexToEntRef(entity)); }

bool Cooling(int client, ConVar cvar, float last, const char[] label, bool notify)
{
    float seconds = cvar.FloatValue;
    if (seconds <= 0.0) return false;
    float remaining = seconds - (GetGameTime() - last);
    if (remaining <= 0.0) return false;
    if (notify) PrintToChat(client, "[抽奖] %s 冷却剩余 %.2f 秒。", label, remaining);
    if (g_Debug.BoolValue) LogMessage("[Cooldown] %N %s remaining=%.3f configured=%.3f", client, label, remaining, seconds);
    return true;
}

public Action CmdJerk(int client, int args)
{
    char argument[32]; GetCmdArgString(argument, sizeof(argument)); TrimString(argument);
    if (!StrEqual(argument, "off", false)) { ReplyToCommand(client, "[打胶] 用法：聊天 !jerk off，控制台 sm_jerk off。"); return Plugin_Handled; }
    if (!Human(client) || !Standing(client)) { ReplyToCommand(client, "[打胶] 仅游戏内存活、站立的真人生还者可测试。"); return Plugin_Handled; }
    if (!g_Enable.BoolValue || !g_ConfigReady || g_ChapterClosing) { ReplyToCommand(client, "[打胶] 插件未开启、配置未就绪或章节已结束。"); return Plugin_Handled; }
    if (Cooling(client, g_JerkCooldown, g_LastJerk[client], "打胶测试", true)) return Plugin_Handled;
    if (StartJerk(client)) g_LastJerk[client] = GetGameTime();
    return Plugin_Handled;
}
bool StartJerk(int client)
{
    if (!Standing(client)) return false;
    if (g_JerkTimer[client] != null) { PrintToChat(client, "[打胶] 已在倒计时，不重复启动。"); return false; }
    float seconds = g_JerkDelay.FloatValue;
    g_JerkEnd[client] = GetGameTime() + seconds;
    g_JerkTimer[client] = CreateTimer(seconds < 1.0 ? seconds : 1.0, JerkTick, GetClientUserId(client));
    PrintToChatAll("[打胶] %N 开始打胶，%.2f 秒后完成。", client, seconds);
    return true;
}
public Action JerkTick(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0) return Plugin_Stop;
    if (!AliveSurvivor(client) || !g_Enable.BoolValue || g_ChapterClosing)
    {
        g_JerkTimer[client] = null;
        PrintToChatAll("[打胶] %N 的打胶已中止。", client);
        return Plugin_Stop;
    }
    float remaining = g_JerkEnd[client] - GetGameTime();
    if (remaining > 0.001)
    {
        PrintToChat(client, "[打胶] 还剩 %.1f 秒。", remaining);
        g_JerkTimer[client] = CreateTimer(remaining < 1.0 ? remaining : 1.0, JerkTick, userid);
        return Plugin_Stop;
    }
    // Clear before self-death can trigger the common cleanup callback.
    g_JerkTimer[client] = null;
    float origin[3]; GetClientAbsOrigin(client, origin);
    PrintToChatAll("%N成功打胶", client);
    int hp = GetClientHealth(client) - g_JerkDamage.IntValue;
    if (hp <= 0) ForcePlayerSuicide(client);
    else SetEntityHealth(client, hp);
    float pos[3], radius = g_JerkRadius.FloatValue;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        GetClientAbsOrigin(i, pos);
        if (GetVectorDistance(origin, pos) > radius) continue;
        if (GetClientTeam(i) == 2 && g_JerkBile.BoolValue)
            L4D_CTerrorPlayer_OnVomitedUpon(i, i);
        else if (GetClientTeam(i) == 3 && g_JerkKill.BoolValue) ForcePlayerSuicide(i);
    }
    if (g_JerkKill.BoolValue)
    {
        KillJerkEntities("infected", origin, radius);
        KillJerkEntities("witch", origin, radius);
    }
    return Plugin_Stop;
}
void KillJerkEntities(const char[] classname, const float origin[3], float radius)
{
    int entity = -1; float pos[3];
    while ((entity = FindEntityByClassname(entity, classname)) != -1)
    {
        GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
        if (GetVectorDistance(origin, pos) <= radius) AcceptEntityInput(entity, "Kill");
    }
}
