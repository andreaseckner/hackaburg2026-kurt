import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# Goal: To see the route and delays of a specific bus line, and find pain points.

df = pd.read_csv("enter_dataset",
    encoding='utf-16',
    low_memory=False,
    sep=',',
    index_col=False)

# Some pre-processing to convert the column values to datetime, str, etc depending on type.
time_columns = [
    'Ankunft Haltestelle (Tür)', 'Ankunft Haltestelle (Halt)', 'Ankunft PLAN (Haltestelle)',
    'Abfahrt Haltestelle (Tür)', 'Abfahrt Haltestelle (Halt)', 'Abfahrt PLAN (Haltestelle)'
]


for col in time_columns:
    df[col] = df[col].astype(str).str.strip()

    df[col] = df[col].replace({'nan': None, '': None})

    df[col] = pd.to_datetime(df[col], errors='coerce', dayfirst=True)

col = "Betriebstag"
df[col] = df[col].astype(str).str.strip()
df[col] = df[col].replace({'nan': None, '': None})
df['Betriebstag'] = pd.to_datetime(df['Betriebstag'], format='%d.%m.%Y', errors='coerce', dayfirst=True)

df['Ankunft produktiv'] = df['Ankunft produktiv'].map({'Ja': True, 'Nein': False})
df['Abfahrt produktiv'] = df['Abfahrt produktiv'].map({'Ja': True, 'Nein': False})

category_columns = [
    'Fahrtbeginn (Soll-Haltestelle)', 'Fahrtende (Soll-Haltestelle)',
    'Linie', 'Richtung', 'Umlauf'
]
for col in category_columns:
    df[col] = df[col].astype('category')

# finding the route, delays etc. for a specific bus on a specific route.
cond1 = df["Linie"] == 2
cond2 = df["Richtung"] == 2
cond3 = df["Umlauf"] == 203
df_filtered = df.loc[cond1 & cond2 & cond3].copy()
pd.set_option('display.max_columns', None)

df_filtered['Ankunft_Halt_dt'] = pd.to_datetime(df_filtered['Ankunft Haltestelle (Halt)'], errors='coerce')
df_filtered['Ankunft_PLAN_dt'] = pd.to_datetime(df_filtered['Ankunft PLAN (Haltestelle)'], errors='coerce')

df_filtered = df_filtered.sort_values('Ankunft_PLAN_dt')
df_filtered['arrival_delay_sec'] = (df_filtered['Ankunft_Halt_dt'] - df_filtered['Ankunft_PLAN_dt']).dt.total_seconds()
df_filtered['is_start_stop'] = df_filtered['Haltestelle'] == df_filtered['Fahrtbeginn (Soll-Haltestelle)']
df_filtered['trip_id'] = df_filtered['is_start_stop'].cumsum()

trip_records = []
unique_route_paths = set()

for trip_id, group in df_filtered.groupby('trip_id'):
    if trip_id == 0 or group.empty:
        continue

    date = group['Ankunft_Halt_dt'].dt.date.iloc[0]
    planned_start = group['Ankunft_PLAN_dt'].iloc[0].time()
    actual_start = group['Ankunft_Halt_dt'].iloc[0].time()
    actual_end = group['Ankunft_Halt_dt'].iloc[-1].time()
    bus = group['Umlauf'].iloc[0]
    line = group['Linie'].iloc[0]
    direction = group['Richtung'].iloc[0]

    start_stop = group['Unnamed: 10'].iloc[0]
    end_stop = group['Unnamed: 12'].iloc[0]
    route_name = f"{start_stop} -> {end_stop}"

    stop_sequence = group['Unnamed: 14'].tolist()

    path_string = " -> ".join(stop_sequence)

    unique_route_paths.add((route_name, path_string))

    num_stops = len(group)

    delay_in_route = group.iloc[-1]['arrival_delay_sec']

    if group['arrival_delay_sec'].notna().any():
        idx_max_delay = group['arrival_delay_sec'].idxmax()
        highest_delay_stop = group.loc[idx_max_delay, 'Unnamed: 14']
    else:
        highest_delay_stop = "Unknown"

    delayed_stops = group[group['arrival_delay_sec'] > 180]
    if not delayed_stops.empty:
        delay_start_stop = delayed_stops.iloc[0]['Unnamed: 14']
    else:
        delay_start_stop = "No Delay"

    trip_records.append({
        'Date': date,
        'Actual_Start': actual_start,
        'Bus': bus,
        'Line': line,
        'Richtung': direction,
        'Route': route_name,
        'Number_of_Stops': num_stops,
        'sum_Delay_sec': delay_in_route,
        'Delay_Start_Stop': delay_start_stop,
        'max_Delay_Stop': highest_delay_stop
    })

df_bus_routes = pd.DataFrame(trip_records)

pd.set_option('display.max_columns', None)
pd.set_option('display.width', 1000)

patient_zero = df_bus_routes[df_bus_routes['Delay_Start_Stop'] != 'No Delay']

# The stops with the most number of delays
print(patient_zero['Delay_Start_Stop'].value_counts().head(10))

# The routes - to help us find how those spots are connected in the network
print(
    f"\n=== UNIQUE ROUTE PATHS (Line {cond1.args[1] if hasattr(cond1, 'args') else '2'}, Direction {cond2.args[1] if hasattr(cond2, 'args') else '2'}, Bus 203) ===")
for route_title, full_path in unique_route_paths:
    print(f"\nRoute: {route_title}")
    print(full_path)
print("====================================================\n")