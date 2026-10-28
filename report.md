# Model check, 2026-10-28 17:25 UTC

23 forecast runs stored (2026-10-23T20:00Z to 2026-10-28T17:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 5030 | 1.7 | +0.2 | 3.2 | 1.1 | 34 % |
| best_match | 5030 | 1.8 | +0.3 | 3.2 | 1.3 | 32 % |
| **icon_d2** (app today) | 5030 | 1.8 | +0.3 | 3.2 | 1.3 | 32 % |
| ecmwf_aifs025_single | 5030 | 1.8 | +0.5 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 5030 | 2.0 | +0.7 | 3.2 | 1.2 | 35 % |
| dmi_harmonie_arome_europe | 5030 | 2.0 | +1.0 | 3.5 | 1.2 | 40 % |
| ecmwf_ifs025 | 5030 | 2.0 | +1.0 | 3.3 | 1.2 | 44 % |
| meteoswiss_icon_ch2 | 5030 | 2.1 | +1.0 | 3.5 | 1.5 | 36 % |
| meteoswiss_icon_ch1 | 5020 | 2.3 | +1.3 | 3.4 | 1.5 | 37 % |
| geosphere_arome_austria | 5030 | 2.3 | +1.2 | 3.3 | 1.8 | 35 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 4110 | 1.2 | -0.1 | 2.2 | 1.0 | 19 % |
| best_match | 4110 | 1.2 | -0.1 | 2.3 | 1.3 | 18 % |
| **icon_d2** (app today) | 3960 | 1.2 | -0.0 | 2.2 | 1.3 | 18 % |
| ecmwf_aifs025_single | 4110 | 1.3 | +0.4 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 4110 | 1.3 | +0.4 | 2.1 | 1.5 | 21 % |
| meteoswiss_icon_ch2 | 4110 | 1.3 | +0.5 | 2.2 | 1.4 | 19 % |
| dmi_harmonie_arome_europe | 4110 | 1.4 | +0.5 | 2.3 | 1.4 | 23 % |
| ecmwf_ifs025 | 4110 | 1.4 | +0.6 | 2.3 | 1.2 | 30 % |
| geosphere_arome_austria | 4110 | 1.4 | +0.4 | 2.1 | 2.3 | 17 % |
| meteoswiss_icon_ch1 | 1090 | 1.7 | +1.0 | 2.4 | 1.5 | 27 % |

## All points, archive

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 14385 | 0.8 | -0.0 | 1.7 | 1.2 | 10 % |
| **icon_d2** (app today) | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| best_match | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| ecmwf_aifs025_single | 14385 | 0.9 | +0.1 | – | 1.4 | – |
| knmi_harmonie_arome_europe | 14385 | 1.0 | +0.2 | 1.6 | 1.3 | 8 % |
| ecmwf_ifs025 | 14385 | 1.0 | +0.3 | 1.8 | 1.2 | 11 % |
| meteoswiss_icon_ch2 | 14385 | 1.0 | +0.4 | 2.0 | 1.5 | 12 % |
| dmi_harmonie_arome_europe | 14385 | 1.1 | +0.3 | 1.8 | 1.3 | 10 % |
| geosphere_arome_austria | 14385 | 1.1 | +0.4 | 1.6 | 1.7 | 10 % |
| meteoswiss_icon_ch1 | 14385 | 1.1 | +0.5 | 1.9 | 1.6 | 11 % |

## Once a day instead of twice?

Day 1 over all points, from the two scheduled runs (04:40 and 16:40 UTC) and from the 04:40 run alone.

| Model | Hours, twice | Hours, once | Wind error, twice | Wind error, once | Light wrong, twice | Light wrong, once |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 3030 | 950 | 1.54 | 1.16 | 28 % | 21 % |
| best_match | 3030 | 950 | 1.63 | 1.23 | 26 % | 16 % |
| icon_d2 | 3030 | 950 | 1.63 | 1.23 | 26 % | 16 % |
| ecmwf_aifs025_single | 3030 | 950 | 1.66 | 1.24 | – | – |
| knmi_harmonie_arome_europe | 3030 | 950 | 1.76 | 1.28 | 28 % | 18 % |
| ecmwf_ifs025 | 3030 | 950 | 1.82 | 1.39 | 36 % | 30 % |
| dmi_harmonie_arome_europe | 3030 | 950 | 1.82 | 1.37 | 32 % | 21 % |
| meteoswiss_icon_ch2 | 3030 | 950 | 1.90 | 1.34 | 30 % | 19 % |
| meteoswiss_icon_ch1 | 3020 | 940 | 2.05 | 1.46 | 31 % | 19 % |
| geosphere_arome_austria | 3030 | 950 | 2.11 | 1.47 | 29 % | 18 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, best_match, icon_d2).

## icon_d2 vs best_match

121 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 45 |
| staffelsee | 31 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
| kochelsee | 9 |
| tutzinger-rv | 3 |
| ammersee | 1 |

Latest:

| Run | Point | Hour | Differences |
| --- | --- | --- | --- |
| archive | staffelsee | 2026-10-03T00:00Z | temp +2.3 |
| archive | staffelsee | 2026-10-03T01:00Z | temp +2.2 |
| archive | staffelsee | 2026-10-04T00:00Z | temp -2.3 |
| archive | staffelsee | 2026-10-05T18:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-07T00:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-07T18:00Z | temp -2.4 |
| archive | staffelsee | 2026-10-12T18:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-12T22:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-13T04:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-13T19:00Z | temp -2.1 |

## Per point (day 1)

### MRC 1880 launch point, Starnberg

Stations: wind: Wielenbach (Demollstr.) (19.0 km), gust: Wielenbach (Demollstr.) (19.0 km), temp: Attenkam (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 503 | 1.5 | +1.0 | 3.0 | 1.0 | 37 % |
| best_match | 503 | 1.5 | +1.1 | 2.1 | 1.1 | 23 % |
| **icon_d2** (app today) | 503 | 1.5 | +1.1 | 2.1 | 1.1 | 23 % |
| knmi_harmonie_arome_europe | 503 | 1.6 | +1.2 | 2.9 | 0.9 | 34 % |
| ecmwf_aifs025_single | 503 | 1.8 | +1.5 | – | 0.9 | – |
| meteoswiss_icon_ch2 | 503 | 1.9 | +1.7 | 2.5 | 1.2 | 25 % |
| dmi_harmonie_arome_europe | 503 | 1.9 | +1.6 | 2.8 | 1.0 | 33 % |
| meteoswiss_icon_ch1 | 502 | 2.0 | +1.8 | 3.2 | 1.2 | 34 % |
| geosphere_arome_austria | 503 | 2.0 | +1.8 | 2.9 | 1.6 | 26 % |
| ecmwf_ifs025 | 503 | 2.0 | +1.9 | 3.4 | 0.9 | 46 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 503 | 1.0 | +0.2 | 1.6 | 1.0 | 21 % |
| **icon_d2** (app today) | 503 | 1.0 | +0.2 | 1.6 | 1.0 | 21 % |
| icon_eu | 503 | 1.2 | +0.7 | 2.1 | 1.0 | 29 % |
| geosphere_arome_austria | 503 | 1.2 | +0.5 | 2.5 | 1.8 | 29 % |
| knmi_harmonie_arome_europe | 503 | 1.2 | +0.4 | 2.0 | 1.1 | 24 % |
| dmi_harmonie_arome_europe | 503 | 1.4 | +0.8 | 2.7 | 0.8 | 31 % |
| meteoswiss_icon_ch2 | 503 | 1.5 | +1.2 | 2.0 | 1.4 | 22 % |
| meteoswiss_icon_ch1 | 502 | 1.5 | +1.3 | 2.1 | 1.2 | 26 % |
| ecmwf_aifs025_single | 503 | 1.8 | +1.5 | – | 0.9 | – |
| ecmwf_ifs025 | 503 | 2.0 | +1.9 | 3.4 | 0.9 | 46 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 503 | 1.4 | +1.0 | 1.8 | 1.1 | 25 % |
| best_match | 503 | 1.5 | +1.1 | 2.2 | 1.1 | 24 % |
| **icon_d2** (app today) | 503 | 1.5 | +1.1 | 2.2 | 1.1 | 24 % |
| ecmwf_aifs025_single | 503 | 1.8 | +1.5 | – | 0.9 | – |
| knmi_harmonie_arome_europe | 503 | 2.0 | +1.7 | 3.2 | 1.0 | 35 % |
| meteoswiss_icon_ch2 | 503 | 2.0 | +1.9 | 3.1 | 1.5 | 35 % |
| ecmwf_ifs025 | 503 | 2.0 | +1.9 | 3.4 | 0.9 | 46 % |
| dmi_harmonie_arome_europe | 503 | 2.4 | +2.2 | 3.8 | 1.1 | 44 % |
| geosphere_arome_austria | 503 | 2.4 | +2.2 | 2.6 | 1.7 | 28 % |
| meteoswiss_icon_ch1 | 502 | 3.2 | +3.1 | 3.0 | 1.7 | 35 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 503 | 1.0 | -0.0 | 1.6 | 1.1 | 24 % |
| **icon_d2** (app today) | 503 | 1.0 | -0.0 | 1.6 | 1.1 | 24 % |
| icon_eu | 503 | 1.0 | -0.1 | 1.9 | 1.1 | 26 % |
| knmi_harmonie_arome_europe | 503 | 1.3 | +0.3 | 2.2 | 1.0 | 24 % |
| meteoswiss_icon_ch1 | 502 | 1.3 | +0.8 | 2.0 | 1.3 | 25 % |
| dmi_harmonie_arome_europe | 503 | 1.3 | +0.7 | 2.3 | 1.0 | 27 % |
| ecmwf_aifs025_single | 503 | 1.4 | +0.3 | – | 0.9 | – |
| ecmwf_ifs025 | 503 | 1.6 | +0.8 | 2.7 | 1.1 | 39 % |
| geosphere_arome_austria | 503 | 1.9 | +1.7 | 2.1 | 1.9 | 24 % |
| meteoswiss_icon_ch2 | 503 | 1.9 | +1.8 | 2.6 | 1.9 | 34 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 503 | 2.1 | +1.7 | 2.9 | 1.6 | 34 % |
| best_match | 503 | 2.1 | +1.8 | 2.5 | 1.6 | 27 % |
| **icon_d2** (app today) | 503 | 2.1 | +1.8 | 2.5 | 1.6 | 27 % |
| ecmwf_aifs025_single | 503 | 2.2 | +1.9 | – | 1.5 | – |
| meteoswiss_icon_ch2 | 503 | 2.2 | +1.9 | 3.4 | 1.5 | 35 % |
| dmi_harmonie_arome_europe | 503 | 2.3 | +2.1 | 5.1 | 1.8 | 51 % |
| ecmwf_ifs025 | 503 | 2.6 | +2.5 | 4.1 | 1.3 | 54 % |
| knmi_harmonie_arome_europe | 503 | 2.8 | +2.7 | 4.3 | 1.9 | 43 % |
| meteoswiss_icon_ch1 | 502 | 3.3 | +3.1 | 3.1 | 2.7 | 37 % |
| geosphere_arome_austria | 503 | 3.9 | +3.9 | 4.1 | 1.9 | 39 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 503 | 1.8 | +1.5 | – | 0.7 | – |
| best_match | 503 | 1.9 | +1.6 | 2.4 | 1.1 | 27 % |
| **icon_d2** (app today) | 503 | 1.9 | +1.6 | 2.4 | 1.1 | 27 % |
| icon_eu | 503 | 2.0 | +1.7 | 3.3 | 0.9 | 38 % |
| ecmwf_ifs025 | 503 | 2.0 | +1.9 | 3.4 | 1.0 | 46 % |
| knmi_harmonie_arome_europe | 503 | 2.1 | +1.8 | 3.3 | 0.8 | 34 % |
| meteoswiss_icon_ch2 | 503 | 2.4 | +2.2 | 3.4 | 0.7 | 36 % |
| geosphere_arome_austria | 503 | 2.5 | +2.4 | 4.0 | 1.2 | 36 % |
| meteoswiss_icon_ch1 | 502 | 2.6 | +2.4 | 3.5 | 0.8 | 35 % |
| dmi_harmonie_arome_europe | 503 | 2.7 | +2.6 | 3.5 | 0.8 | 39 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 503 | 1.2 | +1.0 | – | 1.5 | – |
| icon_eu | 503 | 1.3 | +0.8 | 5.7 | 1.0 | 50 % |
| dmi_harmonie_arome_europe | 503 | 2.3 | +2.2 | 4.7 | 1.4 | 50 % |
| knmi_harmonie_arome_europe | 503 | 2.4 | +2.3 | 4.6 | 1.2 | 49 % |
| **icon_d2** (app today) | 503 | 2.4 | +2.3 | 7.6 | 1.2 | 68 % |
| best_match | 503 | 2.4 | +2.3 | 7.6 | 1.2 | 68 % |
| ecmwf_ifs025 | 503 | 2.5 | +2.3 | 3.7 | 1.8 | 47 % |
| geosphere_arome_austria | 503 | 2.6 | +2.1 | 4.3 | 1.9 | 46 % |
| meteoswiss_icon_ch2 | 503 | 2.9 | +2.8 | 7.5 | 1.2 | 69 % |
| meteoswiss_icon_ch1 | 502 | 3.2 | +3.1 | 8.0 | 1.2 | 68 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 503 | 1.1 | -0.4 | – | 1.1 | – |
| ecmwf_ifs025 | 503 | 1.1 | +0.1 | 1.9 | 1.4 | 25 % |
| meteoswiss_icon_ch2 | 503 | 1.3 | -0.3 | 2.5 | 2.0 | 25 % |
| knmi_harmonie_arome_europe | 503 | 1.3 | -0.1 | 2.1 | 1.2 | 27 % |
| best_match | 503 | 1.4 | -0.9 | 2.4 | 1.4 | 23 % |
| **icon_d2** (app today) | 503 | 1.4 | -0.9 | 2.4 | 1.4 | 23 % |
| dmi_harmonie_arome_europe | 503 | 1.4 | +0.2 | 2.4 | 1.2 | 36 % |
| geosphere_arome_austria | 503 | 1.4 | -0.3 | 2.7 | 2.2 | 35 % |
| meteoswiss_icon_ch1 | 502 | 1.4 | -0.4 | 2.5 | 1.3 | 35 % |
| icon_eu | 503 | 1.5 | -1.0 | 2.1 | 0.9 | 25 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 502 | 3.2 | -3.2 | 5.2 | 2.5 | 45 % |
| dmi_harmonie_arome_europe | 503 | 3.6 | -3.4 | 6.2 | 1.5 | 57 % |
| ecmwf_ifs025 | 503 | 3.7 | -3.7 | 5.7 | 1.2 | 57 % |
| geosphere_arome_austria | 503 | 3.7 | -3.6 | 6.0 | 2.2 | 56 % |
| knmi_harmonie_arome_europe | 503 | 3.8 | -3.7 | 6.2 | 1.4 | 53 % |
| meteoswiss_icon_ch2 | 503 | 3.9 | -3.9 | 6.4 | 2.6 | 55 % |
| ecmwf_aifs025_single | 503 | 4.2 | -4.2 | – | 1.0 | – |
| icon_eu | 503 | 4.2 | -4.2 | 7.7 | 1.6 | 62 % |
| **icon_d2** (app today) | 503 | 4.5 | -4.5 | 7.8 | 2.6 | 60 % |
| best_match | 503 | 4.5 | -4.5 | 7.8 | 2.6 | 60 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 503 | 0.8 | +0.0 | 1.3 | 0.9 | 19 % |
| best_match | 503 | 0.8 | -0.0 | 1.4 | 0.9 | 23 % |
| **icon_d2** (app today) | 503 | 0.8 | -0.0 | 1.4 | 0.9 | 23 % |
| ecmwf_aifs025_single | 503 | 0.9 | +0.6 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 503 | 0.9 | +0.5 | 1.5 | 1.1 | 26 % |
| ecmwf_ifs025 | 503 | 0.9 | +0.6 | 1.6 | 1.2 | 31 % |
| knmi_harmonie_arome_europe | 503 | 1.0 | +0.5 | 1.7 | 1.1 | 28 % |
| dmi_harmonie_arome_europe | 503 | 1.0 | +0.6 | 1.8 | 1.2 | 32 % |
| meteoswiss_icon_ch1 | 502 | 1.0 | +0.8 | 1.8 | 1.1 | 31 % |
| geosphere_arome_austria | 503 | 1.6 | +1.3 | 2.0 | 1.9 | 30 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
