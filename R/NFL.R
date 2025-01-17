# Install necessary packages
install.packages(c("nflreadr", "dplyr", "stringr", "readxl", "writexl", "sqldf"))

# Load the necessary packages
library(c("nflreadr", "dplyr", "stringr", "readxl", "writexl", "sqldf"))

#Set working directory
setwd("C:/Users/Yoshi Aher/Desktop/NFL")

# Load NFL play by play data for the 2024 season
NFL_2024 <- load_pbp(2024)

# Load player statistics for the 2024 season
player_stats_2024 <- load_player_stats(2024)

#=========================================================
# PART 1: AGGREGATING INDIVIDUAL PLAYOFF QB STATS FOR THE 
# SEASON
#=========================================================

# Filter for regular season quarterbacks with at least 10 games played
player_stats <- player_stats_2024 %>%
  filter(season_type == "REG" & position == "QB") %>% 
  group_by(player_name, recent_team) %>%
 
# Calculate various quarterback statistics
  summarize(
    completions = sum(completions),
    attempts = sum(attempts),
    cmp_pct = completions / attempts, 
    yards = sum(passing_yards),
    touchdowns = sum(passing_tds),
    pass_touchdowns = sum(passing_tds),
    rush_touchdowns = sum(rushing_tds),
    total_touchdowns = sum(passing_tds) + sum(rushing_tds),
    td_pct = pass_touchdowns / attempts * 100,
    interceptions = sum(interceptions),
    int_pct = interceptions / attempts * 100,
    first_down = sum(passing_first_downs),
    yards_attempt = yards / attempts,
    adj_yards_attempt = (yards + 20 * pass_touchdowns - 45 * interceptions) / attempts, 
    yards_completions = yards / completions,
    yards_game = yards / 17,  # Assuming a 17-game season
    sacks = sum(sacks),
    sack_yards = sum(sack_yards),
    sack_pct = sacks / (attempts + sacks) * 100
  )


# Create a data frame named 'playoff_tms' containing a single column 'team' 
# with the names of 14 teams that qualified for the NFL playoffs. 
playoff_tms_vector <- c("KC", "BUF", "BAL", "HOU", "LAC", "PIT", "DEN", "DET", "PHI", "TB", "LA", "MIN", "WAS", "GB")
playoff_tms <- data.frame(team=playoff_tms_vector)

#Subset player_stats for playoff QBs
player_stats <- sqldf("select a.*, b.* from playoff_tms as a left join player_stats as b on a.team=b.recent_team")

#Remove record with J.Fields because Russell Wilson started more games for the Steelers
player_stats <- player_stats %>% 
     filter(player_name != "J.Fields")

# Write thee player_stats dataframe to an Excel file
write.xlsx(player_stats, "player_stats.xlsx")
#==================================================================
# PART 2: AGGREGATING AND RANKING TEAM LEVEL STATS FOR THE OFFENSIVE 
# LINE, DEFENSE, SCHEDULE DIFFICULTY, AND RECEIVING CORE 
#==================================================================
# Load passing statistics for the 2024 season
passing_2024 <- load_pfr_advstats(stat_type = 'pass', summary_level = 'season', seasons = 2024)

# Clean player names by extracting initials and full last name (Ex. Joe Burrow --> J.Burrow)
passing_2024 <- passing_2024 %>% 
    mutate(
        player_name = paste0(substr(player, 1, 1), ".", str_trim(str_extract(player, "\\s+.+"))) 
    )

# Filter passing statistics to include only playoff QBs 
passing_2024 <- sqldf("select * from passing_2024 where player_name in (select player_name from player_stats)")

# Extract player names and sack data from the 'player_stats' dataset
qb_sacks <- player_stats %>% 
    select(player_name, sacks)

# Join sack data with passing statistics based on player name
all_oline_stats <- sqldf("select a.sacks, b.* from qb_sacks as a inner join passing_2024 as b on a.player_name=b.player_name")

# Standardize (z-score) relevant offensive line metrics
oline_rank <- all_oline_stats %>%
    mutate(
        z_sacks = (sacks - mean(sacks)) / sd(sacks),
        z_pocket_time = (pocket_time - mean(pocket_time)) / sd(pocket_time),
        z_pressure_pct = (pressure_pct - mean(pressure_pct)) / sd(pressure_pct),
        z_times_hurried = (times_hurried - mean(times_hurried)) / sd(times_hurried),
        z_times_hit = (times_hit - mean(times_hit)) / sd(times_hit),
        w_sacks = -0.30,  # Negative weight for sacks allowed
        w_pocket_time = 0.20,
        w_pressure_pct = -0.25,  # Negative weight for higher pressure percentage
        w_times_hurried = -0.15,  # Negative weight for more hurries
        w_times_hit = -0.10
    ) %>%
    # Calculate a weighted score based on standardized metrics and assigned weights
    mutate(
        weighted_score = 
            (z_sacks * w_sacks) + 
            (z_pocket_time * w_pocket_time) + 
            (z_pressure_pct * w_pressure_pct) + 
            (z_times_hurried * w_times_hurried) + 
            (z_times_hit * w_times_hit)
    )

# Write the final offensive line stats to an Excel file
write.xlsx(oline_rank, "oline_rank.xlsx")

# Read in basic defensive team stats from Pro-Football Reference
pro_def <- read.xlsx("Pro_Def_Stats.xlsx", sep = "\t")  # Assuming data is tab-delimited

# Read in pass rush team stats from Pro-Football Reference
pro_def_PR <- read.xlsx("Pro_Def_PR.xlsx", sep = "\t")  # Assuming data is tab-delimited

# Read in 3rd and 4th down conversion stats from Pro-Football Reference
pro_def_conv <- read.xlsx("Pro_Def_Conv.xlsx", sep = "\t")  # Assuming data is tab-delimited

# Merge defensive stats with conversion stats on Team name
team_defense <- merge(x = pro_def, y = pro_def_conv, by = "Tm")

# Merge the merged data with pass rush stats on Team name
team_defense <- merge(x = team_defense, y = pro_def_PR, by = "Tm")

# Calculate Z-scores for defensive metrics
team_defense_final <- team_defense %>%
  mutate(
    z_PA = (PA - mean(PA)) / sd(PA),  # Standardized Passing Attempts
    z_Total_Yds_Allowed = (Total_Yds_Allowed - mean(Total_Yds_Allowed)) / sd(Total_Yds_Allowed),  # Standardized Total Yards Allowed
    z_Total_Turnovers = (Total_Turnovers - mean(Total_Turnovers)) / sd(Total_Turnovers),  # Standardized Total Turnovers
    z_ThirdD_Pct = (ThirdD_Pct - mean(ThirdD_Pct)) / sd(ThirdD_Pct),  # Standardized 3rd Down Stop Percentage
    z_RZPct = (RZPct - mean(RZPct)) / sd(RZPct),  # Standardized Red Zone Stop Percentage
    z_Hurries = (Hurries - mean(Hurries)) / sd(Hurries),  # Standardized QB Hurries
    z_Sacks = (Sacks - mean(Sacks)) / sd(Sacks),  # Standardized Sacks
    z_Pressures = (Pressures - mean(Pressures)) / sd(Pressures)  # Standardized QB Pressures
  )

# Create a weighted defensive score using standardized metrics
team_defense_final <- team_defense_final %>%
  mutate(
    weighted_score =
      (z_PA * -.30) +  # Weight Passing Attempts Allowed (-0.3)
      (z_Total_Yds_Allowed * -.20) +  # Weight Total Yards Allowed (-0.2)
      (z_Total_Turnovers * .30) +  # Weight Total Turnovers (0.3)
      (z_ThirdD_Pct * -.10) +  # Weight 3rd Down Stop Percentage (-0.1)
      (z_RZPct * -.15) +  # Weight Red Zone Stop Percentage (-0.15)
      (z_Hurries * .05) +  # Weight QB Hurries (0.05)
      (z_Sacks * .20) +  # Weight Sacks (0.2)
      (z_Pressures * .15)  # Weight QB Pressures (0.15)
  )

# Join defensive stats with team abbreviations so defensive data can be merged with other team level data frames later
team_defense_final <- sqldf("select a.*, b.Abbreviation as abbr from team_defense_final as a left join team_abbr as b on a.Tm=b.Name")

# Fix abbreviation for Los Angeles Rams 
team_defense_final <- team_defense_final %>%
  mutate(
    Team = ifelse(abbr=="LAR", "LA", abbr)
  )

# Filter for playoff teams only 
team_defense_final <- sqldf("select * from team_defense_final where team in (select team from player_stats)")

# Assign defensive rank based on descending weighted score
team_defense_final <- team_defense_final %>%
  mutate(
    def_rank = dense_rank(desc(weighted_score))  
  )

# Write the final defensive stats to an Excel file
write.xlsx(team_defense_final, "team_defense_final.xlsx")

# Filter for regular season games and relevant receiver positions
receiving_stats <- player_stats_2024 %>%
  filter(season_type == "REG" & position %in% c("WR", "TE")) %>%

  # Group by team and summarize key receiving statistics
  group_by(recent_team) %>%
  summarize(
    games_played = n_distinct(week),       # Number of games played
    Yds = sum(receiving_yards),            # Total receiving yards
    YAC = sum(receiving_yards_after_catch), # Total yards after the catch
    YAC_per_rec = YAC / sum(receptions),   # Average yards after the catch per reception
    recs = sum(receptions),               # Total receptions
    tgts = sum(targets),                  # Total targets
    catch_pct = sum(receptions) / sum(targets), # Catch percentage
    Yds_per_Rec = sum(receiving_yards) / sum(receptions), # Yards per reception
    rec_epa = sum(receiving_epa),          # Total receiving EPA
    rec_fumbles = sum(receiving_fumbles),   # Total receiving fumbles
    rec_tds = sum(receiving_tds),          # Total receiving touchdowns
    airyds_per_reception = sum(receiving_air_yards) / sum(receptions)  # Average air yards per reception
  )

# Filter for teams that made the playoffs
receiving_stats <- sqldf("select * from receiving_stats where recent_team in (select team from playoff_tms)")

# Calculate standardized (z-score) values for key receiving metrics
team_receiving_stats <- receiving_stats %>%
  mutate(
    z_Yds = (Yds - mean(Yds)) / sd(Yds),
    z_YAC = (YAC - mean(YAC)) / sd(YAC),
    z_YAC_per_rec = (YAC_per_rec - mean(YAC_per_rec)) / sd(YAC_per_rec),
    z_catch_pct = (catch_pct - mean(catch_pct)) / sd(catch_pct),
    z_Yds_per_Rec = (Yds_per_Rec - mean(Yds_per_Rec)) / sd(Yds_per_Rec),
    z_airyds_per_reception = (airyds_per_reception - mean(airyds_per_reception)) / sd(airyds_per_reception),
    z_rec_tds = (rec_tds - mean(rec_tds)) / sd(rec_tds)
  ) %>%

  # Calculate a weighted receiving score based on standardized metrics
  mutate(
    rec_weighted_score =
      (z_Yds * 0.25) +  # Weight receiving yards (25%)
      (z_YAC * 0.20) +  # Weight yards after the catch (20%)
      (z_YAC_per_rec * 0.15) +  # Weight YAC per reception (15%)
      (z_catch_pct * 0.10) +  # Weight catch percentage (10%)
      (z_Yds_per_Rec * 0.15) +  # Weight yards per reception (15%)
      (z_airyds_per_reception * 0.10) +  # Weight air yards per reception (10%)
      (z_rec_tds * 0.15)  # Weight receiving touchdowns (15%)
  ) %>%

  # Rank teams based on descending weighted receiving score
  mutate(
    rec_rank = dense_rank(desc(rec_weighted_score))
  )

# Write the final receiving stats to an Excel file
write.xlsx(team_receiving_stats, "team_receiving_stats.xlsx")

#Read in Strength of Schedule Data
SoS <- read.xlsx("Team Names and Schedule.xlsx")

# Join schedule strength data with team abbreviations so abbr can be used to merge SoS with other team level data frames later. Filtering again for playoff teams only
SoS <- sqldf("select a.rank as sched_rank, b.abbr as team from SoS as a left join team_abbr as b on a.Team=b.Name where b.abbr in (select team from player_stats)")

# Assign playoff schedule rank based on descending strength of schedule rank
SoS <- SoS %>%
  mutate(
    playoff_sched_rank = dense_rank(desc(sched_rank))
  )

# Join multiple dataframes to create a combined offensive line, schedule strength, receiving, and defense ranking table
oline_SoS_rec_defense <- sqldf("
SELECT
  o.player,  # Player name (from oline_rank)
  o.team,    # Team name (from oline_rank)
  o.oline_rank AS oline_rank,  # Offensive line rank (from oline_rank)
  s.playoff_sched_rank AS sos_rank,  # Playoff schedule rank (from SoS)
  c.rec_rank AS receiving_rank,  # Receiving rank (from team_receiving_stats)
  d.def_rank AS defense_rank  # Defensive rank (from team_defense_final)
FROM oline_rank AS o
LEFT JOIN SoS AS s ON o.team = s.team  # Join on team
LEFT JOIN team_receiving_stats AS c ON o.team = c.recent_team  # Join on team
LEFT JOIN team_defense_final AS d ON o.team = d.team  # Join on team
")

# Write the combined data to an Excel file
write.xlsx(oline_SoS_rec_defense, "oline_SoS_rec_defense.xlsx")

#=======================================================
# PART 3: CREATE DATA FRAME THAT HAS COMPLETION PERCENTAGE 
# UNDER AND WITHOUT PRESSURE AND CALCULATE THE DIFFERENCE
#=======================================================

# Filter for plays where the QB was under pressure (scrambled or hit) and attempting a pass
pressure_comp_pct <- NFL_2024 %>%
  filter(season_type == "REG" & (qb_scramble == 1 | qb_hit == 1) & pass_attempt == 1) %>% 
  group_by(passer_player_name) %>% 
  summarize(
    press_comp_pct = sum(complete_pass) / sum(pass_attempt) # Calculate completion percentage under pressure
  )

# Filter for plays where the QB was not under pressure and attempting a pass
nopressure_comp_pct <- NFL_2024 %>%
  filter(season_type == "REG" & qb_scramble == 0 & qb_hit == 0 & pass_attempt == 1) %>%
  group_by(passer_player_name) %>%
  summarize(
    nopress_comp_pct = sum(complete_pass) / sum(pass_attempt) # Calculate completion percentage without pressure
  )

# Filter for playoff QBs
pressure_comp_pct <- sqldf("select * from pressure_comp_pct where passer_player_name in (select player_name from player_stats)")
nopressure_comp_pct <- sqldf("select * from nopressure_comp_pct where passer_player_name in (select player_name from player_stats)")

# Join the two dataframes on quarterback name
pressure_nopress <- sqldf("select a.*, b.press_comp_pct from nopressure_comp_pct as a left join pressure_comp_pct as b on a.passer_player_name=b.passer_player_name")

# Calculate the difference in completion percentage under and without pressure
pressure_nopress <- pressure_nopress %>%
  mutate(
    difference = abs(nopress_comp_pct - press_comp_pct) 
  )

# Write the results to an Excel file
write.xlsx(pressure_nopress, "pressure_nopress.xlsx")

#====================================================


# Filter and Prepare Quarterback EPA Data
qb_epa <- NFL_2024 %>%
  filter(season_type == "REG") %>%
  filter(!is.na(qb_epa)) %>%  # Filter for rows with valid EPA data
  group_by(passer_player_name, week) %>%
  summarize(mean_epa = mean(qb_epa), .groups = "drop") %>%  # Calculate mean EPA for each player per week and then ungroup
  group_by(week) %>%
  summarize(
    league_average_epa = mean(mean_epa)  # Calculate league average EPA as the mean of all player means per week
  ) %>%
  ungroup()

# Create data frame that stores player name, opponents played against, and the week they played that opponent
opp <- player_stats %>% select(player_name, week, opponent_team)

# Merge Quarterback EPA with Opponent Data
qb_epa_opp <- merge(
qb_epa,
opp,
by.x = c("passer_player_name", "week"),  # Columns in qb_epa
by.y = c("player_name", "week")          # Columns in opp
)

#Subset EPA data for playoff QBs only 
qb_epa_opp <- sqldf("select * from qb_epa_opp where passer_player_name in (select player_name from player_stats)")

# Write qb_epa_opp data to Excel
write_xlsx(third_down_data, "third_down_data.xlsx")

third_down_data <- NFL_2024 %>%
  filter(season_type == "REG" & down == 3) %>% 
  mutate(
    third_down_bucket = case_when(
      ydstogo <= 3 ~ "Short (1-3)",
      ydstogo >= 4 & ydstogo <= 6 ~ "Medium (4-6)",
      ydstogo >= 7 & ydstogo <= 9 ~ "Long (7-9)",
      TRUE ~ "Very Long (10+)" 
    )
  ) %>%
  group_by(passer_player_name, third_down_bucket) %>%
  summarize(
    conversion_rate = mean(ifelse(yards_gained >= ydstogo, 1, 0)),
    total_attempts = n(),
    .groups = "drop" 
  )


#Subset third down data for playoff QBs only 
third_down_data <- sqldf("select * from third_down_data where passer_player_name in (select player_name from player_stats)")

# Write third_down_data to Excel
write_xlsx(third_down_data, "third_down_data.xlsx")

