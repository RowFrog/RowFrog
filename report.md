# Model check, 2026-11-02 17:28 UTC

33 forecast runs stored (2026-10-23T20:00Z to 2026-11-02T17:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 7530 | 1.4 | +0.1 | 2.7 | 1.1 | 26 % |
| best_match | 7530 | 1.5 | +0.2 | 2.7 | 1.3 | 25 % |
| **icon_d2** (app today) | 7530 | 1.5 | +0.2 | 2.7 | 1.3 | 25 % |
| ecmwf_aifs025_single | 7530 | 1.5 | +0.4 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 7530 | 1.7 | +0.6 | 2.8 | 1.2 | 26 % |
| ecmwf_ifs025 | 7530 | 1.7 | +0.8 | 2.8 | 1.2 | 32 % |
| dmi_harmonie_arome_europe | 7530 | 1.7 | +0.8 | 3.0 | 1.2 | 30 % |
| meteoswiss_icon_ch2 | 7530 | 1.7 | +0.8 | 3.0 | 1.4 | 28 % |
| meteoswiss_icon_ch1 | 7520 | 1.9 | +1.0 | 3.0 | 1.5 | 29 % |
| geosphere_arome_austria | 7530 | 1.9 | +0.9 | 2.8 | 1.7 | 26 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 6470 | 1.1 | -0.1 | 2.1 | 1.1 | 15 % |
| best_match | 6470 | 1.1 | -0.0 | 2.1 | 1.3 | 16 % |
| **icon_d2** (app today) | 6220 | 1.1 | +0.0 | 2.1 | 1.3 | 16 % |
| ecmwf_aifs025_single | 6470 | 1.2 | +0.3 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 6470 | 1.2 | +0.3 | 2.0 | 1.5 | 16 % |
| meteoswiss_icon_ch2 | 6470 | 1.2 | +0.4 | 2.1 | 1.4 | 16 % |
| ecmwf_ifs025 | 6470 | 1.3 | +0.5 | 2.1 | 1.3 | 23 % |
| dmi_harmonie_arome_europe | 6470 | 1.3 | +0.4 | 2.2 | 1.4 | 18 % |
| geosphere_arome_austria | 6470 | 1.3 | +0.4 | 2.0 | 2.1 | 14 % |
| meteoswiss_icon_ch1 | 1790 | 1.5 | +0.8 | 2.2 | 1.5 | 21 % |

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
| icon_eu | 5530 | 2200 | 1.25 | 1.01 | 19 % | 14 % |
| best_match | 5530 | 2200 | 1.32 | 1.06 | 19 % | 13 % |
| icon_d2 | 5530 | 2200 | 1.32 | 1.06 | 19 % | 13 % |
| ecmwf_aifs025_single | 5530 | 2200 | 1.35 | 1.09 | – | – |
| knmi_harmonie_arome_europe | 5530 | 2200 | 1.45 | 1.18 | 19 % | 12 % |
| ecmwf_ifs025 | 5530 | 2200 | 1.48 | 1.21 | 23 % | 17 % |
| dmi_harmonie_arome_europe | 5530 | 2200 | 1.50 | 1.21 | 22 % | 14 % |
| meteoswiss_icon_ch2 | 5530 | 2200 | 1.53 | 1.19 | 21 % | 15 % |
| meteoswiss_icon_ch1 | 5520 | 2190 | 1.67 | 1.32 | 23 % | 16 % |
| geosphere_arome_austria | 5530 | 2200 | 1.69 | 1.29 | 19 % | 11 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, icon_d2, best_match).

## icon_d2 vs best_match

127 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 46 |
| staffelsee | 34 |
| starnberger-see-centre | 18 |
| tegernsee | 15 |
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
| icon_eu | 753 | 1.2 | +0.8 | 2.5 | 0.9 | 28 % |
| best_match | 753 | 1.2 | +0.8 | 1.7 | 1.0 | 16 % |
| **icon_d2** (app today) | 753 | 1.2 | +0.8 | 1.7 | 1.1 | 16 % |
| knmi_harmonie_arome_europe | 753 | 1.4 | +0.9 | 2.4 | 0.9 | 23 % |
| ecmwf_aifs025_single | 753 | 1.5 | +1.2 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 753 | 1.5 | +1.3 | 2.0 | 1.0 | 17 % |
| dmi_harmonie_arome_europe | 753 | 1.6 | +1.3 | 2.3 | 1.0 | 24 % |
| meteoswiss_icon_ch1 | 752 | 1.6 | +1.3 | 2.5 | 1.1 | 24 % |
| geosphere_arome_austria | 753 | 1.6 | +1.3 | 2.3 | 1.4 | 18 % |
| ecmwf_ifs025 | 753 | 1.7 | +1.5 | 2.8 | 1.0 | 32 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 753 | 0.9 | +0.3 | 1.5 | 1.0 | 15 % |
| **icon_d2** (app today) | 753 | 0.9 | +0.3 | 1.5 | 1.0 | 15 % |
| icon_eu | 753 | 1.0 | +0.6 | 1.9 | 1.0 | 23 % |
| knmi_harmonie_arome_europe | 753 | 1.1 | +0.3 | 1.8 | 1.0 | 17 % |
| geosphere_arome_austria | 753 | 1.1 | +0.6 | 2.2 | 1.5 | 21 % |
| dmi_harmonie_arome_europe | 753 | 1.3 | +0.8 | 2.5 | 0.9 | 23 % |
| meteoswiss_icon_ch2 | 753 | 1.4 | +1.2 | 2.0 | 1.4 | 18 % |
| ecmwf_aifs025_single | 753 | 1.5 | +1.2 | – | 1.0 | – |
| meteoswiss_icon_ch1 | 752 | 1.6 | +1.4 | 2.2 | 1.2 | 24 % |
| ecmwf_ifs025 | 753 | 1.7 | +1.5 | 2.8 | 1.0 | 32 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 753 | 1.3 | +0.9 | 1.6 | 1.1 | 17 % |
| **icon_d2** (app today) | 753 | 1.3 | +1.0 | 1.9 | 1.0 | 17 % |
| best_match | 753 | 1.3 | +1.0 | 1.9 | 1.0 | 17 % |
| ecmwf_aifs025_single | 753 | 1.5 | +1.2 | – | 1.0 | – |
| ecmwf_ifs025 | 753 | 1.7 | +1.5 | 2.8 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 753 | 1.7 | +1.5 | 2.8 | 1.0 | 25 % |
| meteoswiss_icon_ch2 | 753 | 1.7 | +1.6 | 2.7 | 1.4 | 25 % |
| dmi_harmonie_arome_europe | 753 | 2.0 | +1.8 | 3.3 | 1.1 | 32 % |
| geosphere_arome_austria | 753 | 2.1 | +2.0 | 2.3 | 1.6 | 21 % |
| meteoswiss_icon_ch1 | 752 | 2.7 | +2.7 | 2.5 | 1.9 | 24 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 753 | 0.9 | +0.1 | 1.5 | 1.1 | 17 % |
| **icon_d2** (app today) | 753 | 0.9 | +0.1 | 1.5 | 1.1 | 17 % |
| icon_eu | 753 | 0.9 | -0.1 | 1.6 | 1.0 | 18 % |
| knmi_harmonie_arome_europe | 753 | 1.1 | +0.2 | 1.9 | 1.0 | 17 % |
| meteoswiss_icon_ch1 | 752 | 1.1 | +0.6 | 1.8 | 1.2 | 18 % |
| ecmwf_aifs025_single | 753 | 1.2 | +0.1 | – | 0.9 | – |
| dmi_harmonie_arome_europe | 753 | 1.2 | +0.6 | 2.1 | 1.0 | 19 % |
| ecmwf_ifs025 | 753 | 1.3 | +0.6 | 2.3 | 1.1 | 27 % |
| geosphere_arome_austria | 753 | 1.6 | +1.3 | 1.8 | 1.8 | 17 % |
| meteoswiss_icon_ch2 | 753 | 1.7 | +1.5 | 2.3 | 1.7 | 24 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 753 | 1.6 | +1.3 | 2.3 | 1.5 | 23 % |
| best_match | 753 | 1.7 | +1.3 | 2.0 | 1.5 | 19 % |
| **icon_d2** (app today) | 753 | 1.7 | +1.3 | 2.0 | 1.5 | 19 % |
| meteoswiss_icon_ch2 | 753 | 1.7 | +1.4 | 2.7 | 1.4 | 25 % |
| ecmwf_aifs025_single | 753 | 1.8 | +1.6 | – | 1.5 | – |
| dmi_harmonie_arome_europe | 753 | 1.9 | +1.6 | 4.1 | 1.7 | 37 % |
| ecmwf_ifs025 | 753 | 2.1 | +2.0 | 3.4 | 1.4 | 38 % |
| knmi_harmonie_arome_europe | 753 | 2.2 | +2.1 | 3.5 | 1.7 | 30 % |
| meteoswiss_icon_ch1 | 752 | 2.5 | +2.4 | 2.5 | 2.9 | 25 % |
| geosphere_arome_austria | 753 | 3.0 | +2.9 | 3.2 | 1.8 | 27 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 753 | 1.5 | +1.2 | 2.0 | 1.1 | 19 % |
| **icon_d2** (app today) | 753 | 1.5 | +1.2 | 2.0 | 1.1 | 19 % |
| ecmwf_aifs025_single | 753 | 1.5 | +1.2 | – | 0.9 | – |
| icon_eu | 753 | 1.6 | +1.3 | 2.7 | 0.9 | 28 % |
| ecmwf_ifs025 | 753 | 1.7 | +1.5 | 2.8 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 753 | 1.7 | +1.5 | 2.6 | 0.8 | 23 % |
| meteoswiss_icon_ch2 | 753 | 1.9 | +1.7 | 2.7 | 0.8 | 25 % |
| geosphere_arome_austria | 753 | 2.0 | +1.7 | 3.1 | 1.2 | 25 % |
| meteoswiss_icon_ch1 | 752 | 2.1 | +2.0 | 3.0 | 0.9 | 25 % |
| dmi_harmonie_arome_europe | 753 | 2.1 | +2.0 | 2.8 | 0.8 | 27 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 753 | 1.1 | +0.8 | 4.7 | 1.2 | 38 % |
| ecmwf_aifs025_single | 753 | 1.1 | +0.9 | – | 1.6 | – |
| ecmwf_ifs025 | 753 | 2.1 | +1.9 | 3.1 | 2.0 | 33 % |
| knmi_harmonie_arome_europe | 753 | 2.1 | +2.0 | 4.1 | 1.5 | 37 % |
| dmi_harmonie_arome_europe | 753 | 2.1 | +2.1 | 4.4 | 1.7 | 43 % |
| **icon_d2** (app today) | 753 | 2.1 | +2.0 | 6.8 | 1.5 | 64 % |
| best_match | 753 | 2.1 | +2.0 | 6.8 | 1.5 | 64 % |
| geosphere_arome_austria | 753 | 2.3 | +1.9 | 3.7 | 2.3 | 33 % |
| meteoswiss_icon_ch2 | 753 | 2.5 | +2.4 | 6.6 | 1.5 | 64 % |
| meteoswiss_icon_ch1 | 752 | 2.7 | +2.6 | 7.1 | 1.5 | 65 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 753 | 0.9 | -0.2 | – | 1.1 | – |
| ecmwf_ifs025 | 753 | 1.0 | +0.2 | 1.8 | 1.3 | 18 % |
| meteoswiss_icon_ch2 | 753 | 1.1 | -0.3 | 2.0 | 1.7 | 17 % |
| knmi_harmonie_arome_europe | 753 | 1.1 | +0.1 | 1.8 | 1.4 | 20 % |
| best_match | 753 | 1.1 | -0.7 | 1.9 | 1.3 | 15 % |
| **icon_d2** (app today) | 753 | 1.1 | -0.7 | 1.9 | 1.3 | 15 % |
| geosphere_arome_austria | 753 | 1.1 | -0.3 | 2.2 | 1.9 | 23 % |
| dmi_harmonie_arome_europe | 753 | 1.2 | +0.2 | 2.0 | 1.2 | 25 % |
| icon_eu | 753 | 1.2 | -0.9 | 1.8 | 0.9 | 17 % |
| meteoswiss_icon_ch1 | 752 | 1.2 | -0.3 | 2.1 | 1.2 | 23 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 752 | 2.8 | -2.7 | 4.4 | 2.2 | 39 % |
| dmi_harmonie_arome_europe | 753 | 3.1 | -2.9 | 5.3 | 1.4 | 48 % |
| ecmwf_ifs025 | 753 | 3.1 | -3.1 | 4.8 | 1.1 | 47 % |
| geosphere_arome_austria | 753 | 3.3 | -3.2 | 5.3 | 1.9 | 47 % |
| meteoswiss_icon_ch2 | 753 | 3.3 | -3.2 | 5.3 | 2.3 | 46 % |
| knmi_harmonie_arome_europe | 753 | 3.3 | -3.2 | 5.3 | 1.3 | 46 % |
| ecmwf_aifs025_single | 753 | 3.5 | -3.5 | – | 1.0 | – |
| icon_eu | 753 | 3.7 | -3.7 | 6.6 | 1.3 | 51 % |
| best_match | 753 | 3.7 | -3.7 | 6.4 | 2.2 | 50 % |
| **icon_d2** (app today) | 753 | 3.7 | -3.7 | 6.4 | 2.2 | 50 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 753 | 0.7 | -0.1 | 1.2 | 1.0 | 16 % |
| **icon_d2** (app today) | 753 | 0.7 | -0.1 | 1.2 | 1.0 | 16 % |
| icon_eu | 753 | 0.7 | -0.1 | 1.2 | 1.0 | 14 % |
| meteoswiss_icon_ch2 | 753 | 0.8 | +0.3 | 1.3 | 1.1 | 19 % |
| ecmwf_aifs025_single | 753 | 0.8 | +0.4 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 753 | 0.8 | +0.3 | 1.5 | 1.2 | 21 % |
| ecmwf_ifs025 | 753 | 0.8 | +0.4 | 1.4 | 1.3 | 23 % |
| meteoswiss_icon_ch1 | 752 | 0.8 | +0.5 | 1.5 | 1.1 | 23 % |
| dmi_harmonie_arome_europe | 753 | 0.9 | +0.3 | 1.5 | 1.3 | 23 % |
| geosphere_arome_austria | 753 | 1.3 | +0.8 | 1.7 | 1.9 | 22 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
