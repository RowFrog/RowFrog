# Model check, 2026-10-30 05:21 UTC

26 forecast runs stored (2026-10-23T20:00Z to 2026-10-30T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 6030 | 1.6 | +0.1 | 2.9 | 1.1 | 30 % |
| best_match | 6030 | 1.7 | +0.2 | 2.9 | 1.3 | 29 % |
| **icon_d2** (app today) | 6030 | 1.7 | +0.2 | 2.9 | 1.3 | 29 % |
| ecmwf_aifs025_single | 6030 | 1.7 | +0.5 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 6030 | 1.8 | +0.7 | 3.0 | 1.2 | 30 % |
| dmi_harmonie_arome_europe | 6030 | 1.9 | +0.9 | 3.3 | 1.2 | 35 % |
| ecmwf_ifs025 | 6030 | 1.9 | +0.9 | 3.1 | 1.2 | 38 % |
| meteoswiss_icon_ch2 | 6030 | 1.9 | +0.9 | 3.2 | 1.5 | 32 % |
| meteoswiss_icon_ch1 | 6020 | 2.1 | +1.1 | 3.2 | 1.5 | 33 % |
| geosphere_arome_austria | 6030 | 2.1 | +1.1 | 3.1 | 1.8 | 30 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 5090 | 1.1 | -0.1 | 2.1 | 1.1 | 17 % |
| best_match | 5090 | 1.2 | -0.0 | 2.2 | 1.3 | 17 % |
| **icon_d2** (app today) | 4900 | 1.2 | -0.0 | 2.2 | 1.3 | 17 % |
| ecmwf_aifs025_single | 5090 | 1.2 | +0.4 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 5090 | 1.3 | +0.4 | 2.1 | 1.5 | 18 % |
| meteoswiss_icon_ch2 | 5090 | 1.3 | +0.5 | 2.2 | 1.4 | 18 % |
| dmi_harmonie_arome_europe | 5090 | 1.3 | +0.5 | 2.3 | 1.3 | 21 % |
| ecmwf_ifs025 | 5090 | 1.3 | +0.6 | 2.3 | 1.2 | 26 % |
| geosphere_arome_austria | 5090 | 1.4 | +0.4 | 2.1 | 2.3 | 15 % |
| meteoswiss_icon_ch1 | 1370 | 1.6 | +0.9 | 2.3 | 1.5 | 24 % |

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
| icon_eu | 4030 | 1450 | 1.38 | 1.06 | 23 % | 16 % |
| best_match | 4030 | 1450 | 1.45 | 1.11 | 22 % | 15 % |
| icon_d2 | 4030 | 1450 | 1.45 | 1.11 | 22 % | 15 % |
| ecmwf_aifs025_single | 4030 | 1450 | 1.51 | 1.18 | – | – |
| knmi_harmonie_arome_europe | 4030 | 1450 | 1.60 | 1.23 | 23 % | 14 % |
| dmi_harmonie_arome_europe | 4030 | 1450 | 1.66 | 1.27 | 26 % | 16 % |
| ecmwf_ifs025 | 4030 | 1450 | 1.66 | 1.31 | 28 % | 21 % |
| meteoswiss_icon_ch2 | 4030 | 1450 | 1.70 | 1.24 | 25 % | 16 % |
| meteoswiss_icon_ch1 | 4020 | 1440 | 1.83 | 1.34 | 26 % | 17 % |
| geosphere_arome_austria | 4030 | 1450 | 1.90 | 1.38 | 23 % | 14 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, best_match, icon_d2).

## icon_d2 vs best_match

126 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 46 |
| staffelsee | 34 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
| kochelsee | 10 |
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
| best_match | 603 | 1.4 | +1.0 | 1.9 | 1.1 | 20 % |
| **icon_d2** (app today) | 603 | 1.4 | +1.0 | 1.9 | 1.1 | 20 % |
| icon_eu | 603 | 1.4 | +1.0 | 2.8 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 603 | 1.5 | +1.1 | 2.7 | 0.9 | 29 % |
| ecmwf_aifs025_single | 603 | 1.7 | +1.4 | – | 0.9 | – |
| meteoswiss_icon_ch2 | 603 | 1.7 | +1.5 | 2.2 | 1.1 | 21 % |
| dmi_harmonie_arome_europe | 603 | 1.8 | +1.5 | 2.5 | 1.0 | 28 % |
| meteoswiss_icon_ch1 | 602 | 1.8 | +1.6 | 2.9 | 1.2 | 29 % |
| geosphere_arome_austria | 603 | 1.9 | +1.6 | 2.6 | 1.5 | 22 % |
| ecmwf_ifs025 | 603 | 1.9 | +1.7 | 3.1 | 0.9 | 39 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 603 | 0.9 | +0.2 | 1.5 | 1.0 | 18 % |
| **icon_d2** (app today) | 603 | 0.9 | +0.2 | 1.5 | 1.0 | 18 % |
| icon_eu | 603 | 1.1 | +0.6 | 2.0 | 1.0 | 24 % |
| geosphere_arome_austria | 603 | 1.2 | +0.6 | 2.3 | 1.7 | 25 % |
| knmi_harmonie_arome_europe | 603 | 1.2 | +0.4 | 1.9 | 1.1 | 20 % |
| dmi_harmonie_arome_europe | 603 | 1.4 | +0.9 | 2.6 | 0.9 | 27 % |
| meteoswiss_icon_ch2 | 603 | 1.4 | +1.1 | 1.9 | 1.4 | 19 % |
| meteoswiss_icon_ch1 | 602 | 1.5 | +1.3 | 2.0 | 1.2 | 23 % |
| ecmwf_aifs025_single | 603 | 1.7 | +1.4 | – | 0.9 | – |
| ecmwf_ifs025 | 603 | 1.9 | +1.7 | 3.1 | 0.9 | 39 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 603 | 1.3 | +1.0 | 1.7 | 1.1 | 22 % |
| best_match | 603 | 1.4 | +1.1 | 2.0 | 1.1 | 20 % |
| **icon_d2** (app today) | 603 | 1.4 | +1.1 | 2.0 | 1.1 | 20 % |
| ecmwf_aifs025_single | 603 | 1.7 | +1.4 | – | 0.9 | – |
| knmi_harmonie_arome_europe | 603 | 1.9 | +1.7 | 3.0 | 1.0 | 30 % |
| meteoswiss_icon_ch2 | 603 | 1.9 | +1.8 | 2.9 | 1.4 | 30 % |
| ecmwf_ifs025 | 603 | 1.9 | +1.7 | 3.1 | 0.9 | 39 % |
| dmi_harmonie_arome_europe | 603 | 2.2 | +2.1 | 3.6 | 1.1 | 37 % |
| geosphere_arome_austria | 603 | 2.3 | +2.1 | 2.5 | 1.7 | 25 % |
| meteoswiss_icon_ch1 | 602 | 3.0 | +2.9 | 2.7 | 1.8 | 30 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 603 | 0.9 | +0.0 | 1.5 | 1.0 | 21 % |
| **icon_d2** (app today) | 603 | 0.9 | +0.0 | 1.5 | 1.0 | 21 % |
| icon_eu | 603 | 0.9 | -0.1 | 1.8 | 1.1 | 22 % |
| knmi_harmonie_arome_europe | 603 | 1.2 | +0.3 | 2.0 | 1.0 | 20 % |
| meteoswiss_icon_ch1 | 602 | 1.2 | +0.7 | 1.9 | 1.2 | 22 % |
| ecmwf_aifs025_single | 603 | 1.2 | +0.3 | – | 0.9 | – |
| dmi_harmonie_arome_europe | 603 | 1.3 | +0.7 | 2.2 | 1.0 | 23 % |
| ecmwf_ifs025 | 603 | 1.4 | +0.7 | 2.5 | 1.2 | 33 % |
| geosphere_arome_austria | 603 | 1.7 | +1.5 | 1.9 | 1.9 | 21 % |
| meteoswiss_icon_ch2 | 603 | 1.8 | +1.6 | 2.5 | 1.8 | 29 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 603 | 1.8 | +1.5 | 2.6 | 1.5 | 28 % |
| best_match | 603 | 1.9 | +1.5 | 2.3 | 1.6 | 23 % |
| **icon_d2** (app today) | 603 | 1.9 | +1.5 | 2.3 | 1.6 | 23 % |
| meteoswiss_icon_ch2 | 603 | 1.9 | +1.7 | 3.0 | 1.4 | 30 % |
| ecmwf_aifs025_single | 603 | 2.0 | +1.8 | – | 1.4 | – |
| dmi_harmonie_arome_europe | 603 | 2.1 | +1.9 | 4.6 | 1.8 | 45 % |
| ecmwf_ifs025 | 603 | 2.4 | +2.3 | 3.8 | 1.3 | 46 % |
| knmi_harmonie_arome_europe | 603 | 2.6 | +2.4 | 3.9 | 1.8 | 37 % |
| meteoswiss_icon_ch1 | 602 | 2.9 | +2.7 | 2.8 | 2.8 | 31 % |
| geosphere_arome_austria | 603 | 3.5 | +3.5 | 3.7 | 1.9 | 33 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 603 | 1.7 | +1.4 | 2.2 | 1.2 | 23 % |
| **icon_d2** (app today) | 603 | 1.7 | +1.4 | 2.2 | 1.2 | 23 % |
| ecmwf_aifs025_single | 603 | 1.7 | +1.4 | – | 0.8 | – |
| icon_eu | 603 | 1.8 | +1.5 | 3.0 | 1.0 | 32 % |
| ecmwf_ifs025 | 603 | 1.9 | +1.7 | 3.1 | 1.0 | 39 % |
| knmi_harmonie_arome_europe | 603 | 1.9 | +1.7 | 3.0 | 0.8 | 29 % |
| meteoswiss_icon_ch2 | 603 | 2.1 | +2.0 | 3.0 | 0.8 | 31 % |
| geosphere_arome_austria | 603 | 2.3 | +2.1 | 3.6 | 1.2 | 31 % |
| meteoswiss_icon_ch1 | 602 | 2.3 | +2.2 | 3.2 | 0.9 | 29 % |
| dmi_harmonie_arome_europe | 603 | 2.4 | +2.3 | 3.1 | 0.9 | 33 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 603 | 1.2 | +1.0 | – | 1.6 | – |
| icon_eu | 603 | 1.2 | +0.8 | 5.3 | 1.1 | 46 % |
| dmi_harmonie_arome_europe | 603 | 2.2 | +2.1 | 4.5 | 1.5 | 44 % |
| knmi_harmonie_arome_europe | 603 | 2.2 | +2.2 | 4.3 | 1.3 | 42 % |
| **icon_d2** (app today) | 603 | 2.3 | +2.1 | 7.2 | 1.3 | 66 % |
| best_match | 603 | 2.3 | +2.1 | 7.2 | 1.3 | 66 % |
| ecmwf_ifs025 | 603 | 2.3 | +2.1 | 3.5 | 1.8 | 40 % |
| geosphere_arome_austria | 603 | 2.4 | +2.0 | 4.0 | 2.0 | 39 % |
| meteoswiss_icon_ch2 | 603 | 2.7 | +2.6 | 7.1 | 1.3 | 67 % |
| meteoswiss_icon_ch1 | 602 | 2.9 | +2.8 | 7.5 | 1.4 | 65 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 603 | 1.0 | -0.3 | – | 1.2 | – |
| ecmwf_ifs025 | 603 | 1.0 | +0.1 | 1.8 | 1.4 | 21 % |
| meteoswiss_icon_ch2 | 603 | 1.2 | -0.3 | 2.2 | 1.9 | 21 % |
| knmi_harmonie_arome_europe | 603 | 1.2 | -0.0 | 2.0 | 1.3 | 23 % |
| best_match | 603 | 1.2 | -0.8 | 2.2 | 1.4 | 19 % |
| **icon_d2** (app today) | 603 | 1.2 | -0.8 | 2.2 | 1.4 | 19 % |
| geosphere_arome_austria | 603 | 1.3 | -0.3 | 2.5 | 2.1 | 29 % |
| dmi_harmonie_arome_europe | 603 | 1.3 | +0.2 | 2.2 | 1.2 | 30 % |
| meteoswiss_icon_ch1 | 602 | 1.3 | -0.4 | 2.3 | 1.3 | 29 % |
| icon_eu | 603 | 1.3 | -0.9 | 1.9 | 0.9 | 21 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 602 | 3.0 | -3.0 | 4.9 | 2.4 | 42 % |
| dmi_harmonie_arome_europe | 603 | 3.3 | -3.2 | 5.8 | 1.4 | 52 % |
| ecmwf_ifs025 | 603 | 3.4 | -3.4 | 5.3 | 1.1 | 52 % |
| geosphere_arome_austria | 603 | 3.5 | -3.4 | 5.7 | 2.1 | 51 % |
| knmi_harmonie_arome_europe | 603 | 3.6 | -3.5 | 5.8 | 1.4 | 50 % |
| meteoswiss_icon_ch2 | 603 | 3.6 | -3.6 | 5.9 | 2.5 | 50 % |
| ecmwf_aifs025_single | 603 | 3.9 | -3.9 | – | 1.0 | – |
| icon_eu | 603 | 4.0 | -4.0 | 7.2 | 1.5 | 56 % |
| **icon_d2** (app today) | 603 | 4.2 | -4.2 | 7.2 | 2.5 | 54 % |
| best_match | 603 | 4.2 | -4.2 | 7.2 | 2.5 | 54 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 603 | 0.7 | -0.1 | 1.2 | 0.9 | 17 % |
| best_match | 603 | 0.7 | -0.1 | 1.3 | 1.0 | 20 % |
| **icon_d2** (app today) | 603 | 0.7 | -0.1 | 1.3 | 1.0 | 20 % |
| ecmwf_aifs025_single | 603 | 0.8 | +0.5 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 603 | 0.8 | +0.4 | 1.4 | 1.1 | 22 % |
| knmi_harmonie_arome_europe | 603 | 0.9 | +0.4 | 1.6 | 1.2 | 24 % |
| ecmwf_ifs025 | 603 | 0.9 | +0.5 | 1.5 | 1.3 | 27 % |
| meteoswiss_icon_ch1 | 602 | 0.9 | +0.6 | 1.7 | 1.1 | 27 % |
| dmi_harmonie_arome_europe | 603 | 0.9 | +0.5 | 1.7 | 1.3 | 28 % |
| geosphere_arome_austria | 603 | 1.4 | +1.1 | 1.9 | 1.9 | 26 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
