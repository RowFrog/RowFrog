# Model check, 2026-10-25 05:09 UTC

12 forecast runs stored (2026-10-23T20:00Z to 2026-10-25T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 950 | 1.6 | +0.3 | 3.1 | 1.0 | 31 % |
| ecmwf_aifs025_single | 950 | 1.7 | +0.2 | – | 1.0 | – |
| best_match | 950 | 1.7 | +0.3 | 2.9 | 1.3 | 32 % |
| **icon_d2** (app today) | 950 | 1.7 | +0.3 | 2.9 | 1.3 | 32 % |
| dmi_harmonie_arome_europe | 950 | 1.8 | +0.5 | 3.1 | 1.2 | 34 % |
| knmi_harmonie_arome_europe | 950 | 1.8 | +0.2 | 2.9 | 1.3 | 28 % |
| ecmwf_ifs025 | 950 | 2.1 | +1.0 | 3.5 | 1.2 | 41 % |
| meteoswiss_icon_ch2 | 950 | 2.1 | +0.9 | 3.6 | 1.5 | 35 % |
| geosphere_arome_austria | 950 | 2.1 | +0.8 | 2.9 | 1.5 | 29 % |
| meteoswiss_icon_ch1 | 950 | 2.3 | +1.3 | 3.4 | 1.5 | 35 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 60 | 1.2 | +0.3 | 2.3 | 1.3 | 5 % |
| **icon_d2** (app today) | 60 | 1.4 | +0.5 | 2.6 | 1.4 | 15 % |
| best_match | 60 | 1.4 | +0.5 | 2.6 | 1.5 | 15 % |
| ecmwf_aifs025_single | 60 | 1.4 | +0.6 | – | 1.4 | – |
| meteoswiss_icon_ch2 | 60 | 1.7 | +0.9 | 3.4 | 1.8 | 12 % |
| ecmwf_ifs025 | 60 | 1.7 | +0.7 | 3.3 | 1.2 | 8 % |
| dmi_harmonie_arome_europe | 60 | 1.8 | +1.1 | 3.6 | 1.5 | 8 % |
| meteoswiss_icon_ch1 | 60 | 1.8 | +1.2 | 3.2 | 1.2 | 15 % |
| knmi_harmonie_arome_europe | 60 | 1.8 | +1.0 | 3.5 | 1.5 | 8 % |
| geosphere_arome_austria | 60 | 2.0 | +0.8 | 2.9 | 1.8 | 10 % |

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

## icon_d2 vs best_match

111 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 43 |
| staffelsee | 28 |
| starnberger-see-centre | 17 |
| tegernsee | 12 |
| kochelsee | 8 |
| tutzinger-rv | 3 |

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
| knmi_harmonie_arome_europe | 95 | 1.3 | +0.6 | 2.3 | 0.9 | 18 % |
| best_match | 95 | 1.4 | +1.0 | 2.0 | 1.0 | 18 % |
| **icon_d2** (app today) | 95 | 1.4 | +1.0 | 2.0 | 1.0 | 18 % |
| icon_eu | 95 | 1.4 | +1.0 | 3.3 | 0.7 | 25 % |
| dmi_harmonie_arome_europe | 95 | 1.5 | +1.1 | 2.4 | 0.7 | 18 % |
| ecmwf_aifs025_single | 95 | 1.5 | +1.2 | – | 0.8 | – |
| geosphere_arome_austria | 95 | 1.6 | +1.4 | 2.2 | 0.8 | 18 % |
| meteoswiss_icon_ch2 | 95 | 1.8 | +1.7 | 2.8 | 1.2 | 22 % |
| ecmwf_ifs025 | 95 | 2.0 | +1.9 | 3.8 | 0.8 | 34 % |
| meteoswiss_icon_ch1 | 95 | 2.0 | +2.0 | 3.8 | 1.2 | 32 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 95 | 0.9 | +0.3 | 1.4 | 0.7 | 26 % |
| **icon_d2** (app today) | 95 | 0.9 | +0.3 | 1.4 | 0.7 | 26 % |
| geosphere_arome_austria | 95 | 1.0 | +0.3 | 2.0 | 1.2 | 21 % |
| icon_eu | 95 | 1.1 | +0.8 | 2.4 | 0.7 | 26 % |
| knmi_harmonie_arome_europe | 95 | 1.1 | -0.1 | 1.5 | 1.4 | 22 % |
| dmi_harmonie_arome_europe | 95 | 1.3 | +0.5 | 2.3 | 1.0 | 26 % |
| ecmwf_aifs025_single | 95 | 1.5 | +1.2 | – | 0.8 | – |
| meteoswiss_icon_ch2 | 95 | 1.5 | +1.3 | 2.1 | 1.2 | 22 % |
| meteoswiss_icon_ch1 | 95 | 1.5 | +1.5 | 1.9 | 0.9 | 20 % |
| ecmwf_ifs025 | 95 | 2.0 | +1.9 | 3.8 | 0.8 | 34 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 95 | 1.4 | +1.3 | 1.7 | 0.7 | 24 % |
| ecmwf_aifs025_single | 95 | 1.5 | +1.2 | – | 0.8 | – |
| best_match | 95 | 1.5 | +1.4 | 2.7 | 1.0 | 28 % |
| **icon_d2** (app today) | 95 | 1.5 | +1.4 | 2.7 | 1.0 | 28 % |
| knmi_harmonie_arome_europe | 95 | 1.6 | +1.3 | 2.8 | 0.8 | 20 % |
| dmi_harmonie_arome_europe | 95 | 1.9 | +1.9 | 3.6 | 0.7 | 32 % |
| ecmwf_ifs025 | 95 | 2.0 | +1.9 | 3.8 | 0.8 | 34 % |
| meteoswiss_icon_ch2 | 95 | 2.1 | +2.0 | 3.7 | 1.4 | 34 % |
| geosphere_arome_austria | 95 | 2.2 | +2.1 | 2.2 | 0.8 | 21 % |
| meteoswiss_icon_ch1 | 95 | 4.0 | +4.0 | 3.7 | 1.8 | 36 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 95 | 0.7 | -0.0 | 1.2 | 0.7 | 25 % |
| best_match | 95 | 0.8 | +0.2 | 1.2 | 0.8 | 29 % |
| **icon_d2** (app today) | 95 | 0.8 | +0.2 | 1.2 | 0.8 | 29 % |
| ecmwf_ifs025 | 95 | 0.9 | +0.2 | 2.1 | 1.3 | 39 % |
| ecmwf_aifs025_single | 95 | 1.1 | -0.4 | – | 0.7 | – |
| dmi_harmonie_arome_europe | 95 | 1.1 | +0.3 | 1.7 | 0.8 | 26 % |
| meteoswiss_icon_ch1 | 95 | 1.2 | +0.8 | 1.9 | 0.9 | 32 % |
| knmi_harmonie_arome_europe | 95 | 1.3 | -0.1 | 1.8 | 1.1 | 25 % |
| geosphere_arome_austria | 95 | 1.5 | +1.4 | 1.4 | 1.1 | 18 % |
| meteoswiss_icon_ch2 | 95 | 2.0 | +1.9 | 3.1 | 1.7 | 30 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 95 | 1.8 | +1.6 | 2.1 | 1.6 | 16 % |
| best_match | 95 | 1.8 | +1.6 | 2.1 | 1.6 | 16 % |
| ecmwf_aifs025_single | 95 | 1.8 | +1.7 | – | 1.5 | – |
| dmi_harmonie_arome_europe | 95 | 1.9 | +1.6 | 4.6 | 1.5 | 46 % |
| meteoswiss_icon_ch2 | 95 | 1.9 | +1.8 | 3.7 | 1.5 | 28 % |
| icon_eu | 95 | 2.0 | +1.8 | 3.1 | 1.5 | 21 % |
| knmi_harmonie_arome_europe | 95 | 2.2 | +2.1 | 3.7 | 1.7 | 29 % |
| ecmwf_ifs025 | 95 | 2.7 | +2.7 | 4.5 | 1.4 | 60 % |
| geosphere_arome_austria | 95 | 3.4 | +3.4 | 3.3 | 1.8 | 32 % |
| meteoswiss_icon_ch1 | 95 | 3.4 | +3.4 | 3.5 | 2.1 | 26 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 95 | 1.5 | +1.2 | – | 0.7 | – |
| knmi_harmonie_arome_europe | 95 | 1.6 | +1.3 | 2.5 | 0.9 | 20 % |
| **icon_d2** (app today) | 95 | 1.8 | +1.7 | 2.3 | 1.1 | 15 % |
| best_match | 95 | 1.8 | +1.7 | 2.3 | 1.2 | 15 % |
| icon_eu | 95 | 2.0 | +1.8 | 3.8 | 0.9 | 26 % |
| ecmwf_ifs025 | 95 | 2.0 | +1.9 | 3.8 | 0.8 | 34 % |
| meteoswiss_icon_ch2 | 95 | 2.1 | +2.0 | 3.5 | 0.8 | 26 % |
| geosphere_arome_austria | 95 | 2.1 | +2.1 | 3.5 | 0.8 | 30 % |
| dmi_harmonie_arome_europe | 95 | 2.1 | +2.1 | 3.0 | 0.8 | 24 % |
| meteoswiss_icon_ch1 | 95 | 2.3 | +2.2 | 3.6 | 0.9 | 28 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 95 | 1.3 | +1.0 | – | 1.4 | – |
| icon_eu | 95 | 1.5 | +1.2 | 4.8 | 1.6 | 33 % |
| dmi_harmonie_arome_europe | 95 | 2.1 | +2.1 | 3.1 | 2.1 | 41 % |
| knmi_harmonie_arome_europe | 95 | 2.2 | +2.2 | 3.4 | 1.6 | 32 % |
| geosphere_arome_austria | 95 | 2.4 | +2.0 | 2.9 | 2.8 | 36 % |
| ecmwf_ifs025 | 95 | 2.4 | +2.4 | 3.2 | 2.3 | 33 % |
| **icon_d2** (app today) | 95 | 2.6 | +2.6 | 6.4 | 1.4 | 83 % |
| best_match | 95 | 2.6 | +2.6 | 6.4 | 1.4 | 83 % |
| meteoswiss_icon_ch2 | 95 | 2.9 | +2.9 | 6.4 | 1.6 | 76 % |
| meteoswiss_icon_ch1 | 95 | 3.1 | +3.1 | 6.8 | 1.8 | 80 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 95 | 1.2 | -0.2 | – | 0.8 | – |
| **icon_d2** (app today) | 95 | 1.3 | -0.7 | 2.4 | 1.6 | 24 % |
| best_match | 95 | 1.3 | -0.7 | 2.4 | 1.6 | 24 % |
| knmi_harmonie_arome_europe | 95 | 1.3 | -0.1 | 2.5 | 1.7 | 24 % |
| ecmwf_ifs025 | 95 | 1.3 | +0.4 | 2.4 | 1.1 | 45 % |
| dmi_harmonie_arome_europe | 95 | 1.3 | -0.2 | 2.3 | 1.2 | 30 % |
| icon_eu | 95 | 1.3 | -0.3 | 2.2 | 0.9 | 33 % |
| meteoswiss_icon_ch2 | 95 | 1.4 | -0.3 | 2.8 | 1.9 | 30 % |
| geosphere_arome_austria | 95 | 1.4 | -1.0 | 3.0 | 2.4 | 25 % |
| meteoswiss_icon_ch1 | 95 | 1.6 | -0.7 | 2.5 | 1.2 | 31 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 95 | 3.5 | -3.4 | 4.8 | 3.1 | 52 % |
| dmi_harmonie_arome_europe | 95 | 4.0 | -4.0 | 6.8 | 1.7 | 78 % |
| meteoswiss_icon_ch2 | 95 | 4.2 | -4.2 | 6.3 | 3.3 | 67 % |
| icon_eu | 95 | 4.3 | -4.3 | 7.5 | 2.0 | 77 % |
| ecmwf_ifs025 | 95 | 4.3 | -4.3 | 6.3 | 1.5 | 70 % |
| geosphere_arome_austria | 95 | 4.5 | -4.5 | 7.0 | 1.7 | 78 % |
| best_match | 95 | 4.6 | -4.6 | 7.3 | 3.2 | 70 % |
| **icon_d2** (app today) | 95 | 4.6 | -4.6 | 7.3 | 3.2 | 70 % |
| knmi_harmonie_arome_europe | 95 | 4.7 | -4.7 | 7.3 | 1.7 | 78 % |
| ecmwf_aifs025_single | 95 | 5.0 | -5.0 | – | 1.9 | – |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 95 | 0.7 | -0.1 | 1.0 | 0.5 | 11 % |
| best_match | 95 | 0.7 | -0.1 | 1.0 | 0.5 | 11 % |
| dmi_harmonie_arome_europe | 95 | 0.7 | -0.0 | 1.3 | 1.1 | 13 % |
| ecmwf_aifs025_single | 95 | 0.7 | +0.2 | – | 0.6 | – |
| knmi_harmonie_arome_europe | 95 | 0.7 | -0.1 | 1.3 | 1.0 | 14 % |
| icon_eu | 95 | 0.8 | -0.3 | 1.3 | 0.6 | 20 % |
| meteoswiss_icon_ch1 | 95 | 0.8 | +0.5 | 1.3 | 0.7 | 11 % |
| ecmwf_ifs025 | 95 | 0.9 | +0.5 | 1.6 | 0.6 | 21 % |
| meteoswiss_icon_ch2 | 95 | 1.0 | +0.1 | 1.4 | 0.7 | 11 % |
| geosphere_arome_austria | 95 | 1.0 | +0.8 | 1.1 | 1.3 | 10 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
