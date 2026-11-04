# P9-V — Transcrire les vocaux Signal de Yoann

*Étude et mesures du 04/11/2026. Dépôt : relance (`aiguillage_signal`, `aiguillage_memoire`).*

**Arrêté par Alexandre le 04/11, après les mesures : aucune transcription n'est codée, aucun moteur n'est retenu.** Les
pièces jointes restent activées et la purge reste en service. La section « Reste à faire » ne sert que si le sujet
reprend.

## Décisions d'Alexandre (04/11)

- Le texte transcrit part dans la **Note à moi-même** Signal. Il n'entre pas dans la mémoire, donc ne part pas vers
  l'API Claude avec les résumés de nuit.
- Transcription locale : aucun vocal vers un service tiers.
- Moteur (Mac Studio ou NUC) : non retenu, sujet arrêté après les mesures ci-dessous.

## Fait le 04/11

- Purge étendue à toutes les pièces jointes, groupes compris, avec balayage de nuit (`ids_pieces`, `noter_pieces`,
  `_purger_pieces`). Déployé à 15 h 08 (sauvegardes `*.avant-purge-20261104`).
- `JSON_RPC_IGNORE_ATTACHMENTS` à `false`, add-on redémarré à 15 h 11. Sans ce réglage, aucune pièce jointe n'était
  téléchargée : les photos de la Note à moi-même (P9-R) ne pouvaient donc pas marcher (déduit du code, à vérifier
  avec une vraie photo).

## Mesures (voix synthétique française, pas une vraie note vocale)

| Machine | Modèle | Vitesse | Mémoire | Texte |
|---|---|---|---|---|
| Mac Studio M1 Max | whisper.cpp `large-v3-turbo-q5_0` | 2 min 16 en 5,9 s (23 × le temps réel) | non mesurée | sans faute sur l'extrait relu |
| Mac Studio M1 Max | whisper.cpp `small` | 2 min 16 en 11,7 s | non mesurée | sans faute sur l'extrait relu |
| NUC | add-on Whisper `small-int8` | 2 min 16 en 85,5 s (1,6 × le temps réel) | 890 Mo | « Gare de Lyon » devient « Gardelion » |

Après l'arrêt, le 04/11 : add-on `core_whisper` désinstallé du NUC et modèles supprimés du Mac.

## Reste à faire

1. Vérifier le format réel et l'`id` d'un vocal reçu (`GET /v1/attachments/<id>`), avec un vrai vocal.
2. Dans `aiguillage_signal`, repérer les vocaux (`contentType` `audio/*`, `voiceNote`) des seules `sources`.
3. Transcrire avec le moteur choisi, avec reprise si le moteur est injoignable.
4. Envoyer le texte dans la Note à moi-même avec un préfixe propre (par exemple « 🎙 ») que `routage` ignore, comme
   « 🤖 », pour qu'il ne parte ni vers l'agent ni vers les consignes de lieu.
5. Essai réel : un vocal de Yoann et une photo dans la Note à moi-même.
