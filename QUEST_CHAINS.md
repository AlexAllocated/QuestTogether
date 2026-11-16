<!-- SPDX-License-Identifier: GPL-3.0-only -->
# Quest chains in Party Quest Log

Open **Party Quest Log** with `/qt pql`, then choose **View chain** beside a
quest's journal button or in its actions menu. The chain-link button turns gold
while open; select it again to close that chain. The chain opens inside the same
list and player columns. One chain section stays open at a time. Clicking an
ordinary quest title still expands its objectives; objective expansions and the
open chain are independent.

The chain control appears only when QT has another related quest to show;
standalone quests keep their ordinary controls. Quest hover tooltips include
quest IDs, so distinct steps with the same title can be told apart. Hidden
future titles stay hidden even when their IDs are shown.

Quest rows display their level and use the game's difficulty colors. Group quests
include `+` after the level, such as `[25+]`. An unknown level appears as `[?]`;
minimum acceptance requirements are shown in the relevant player's cell tooltip
when they do not have the quest. In-progress, ready and completed cells omit
acceptance warnings, as do the general quest-row tooltips.
Future titles are muted. Straight paths stay aligned, with indentation reserved
for branches and their joins. Hover tooltips follow the mouse, including when
the gamepad interface is enabled; controller selection anchors them near the
selected control.

## Sharing from Party Quest Log

The Share column shows current recipient checks before **Share** or **Request
Share**. Hover the action or a missing player's cell for individual status and
known requirements. Confirmed completion, active ownership and known blockers
such as class, level or unmet prerequisites prevent a pointless action. These
checks also run when activating an action, including delayed requests and the
owner's confirmation when current evidence is available.

**Checking eligibility** means evidence is still being fetched. **Eligibility
unknown** means QT cannot establish the remaining conditions; sharing can still
be attempted. **No known blockers** is not a guarantee that the game will accept
the quest. Repeatable quests and unavailable history remain distinct from proof
that a prerequisite was never completed.

Blizzard shares to the entire party, including when PQL displays one selected
player. A share for someone who needs the quest may still produce a refusal for
another member. QT shows the game's specific localized response at the player
level; those messages do not identify a quest and are not treated as new quest
completion or prerequisite evidence.

Completion checks work without QuestieDB on compatible peers. Documented
prerequisite and class/race/level requirements on Forever use compatible
QuestieDB data. Retail quest-line membership alone does not establish those
requirements. Closing PQL releases its history interests, and sharing checks
use the existing bounded history protocol.

## Setup and client coverage

| Client | Data source | What to expect |
| --- | --- | --- |
| Forever | Optional QuestieDB with a compatible public API and Forever data | Related quests, documented prerequisites and other relationships, plus starter locations when the provider supplies valid data. |
| Retail | Blizzard's native quest-line APIs | Native line names and known membership. A line's order does not establish prerequisites or whether a character can accept a quest. |
| Other supported client families | No chain provider in this implementation | Ordinary Party Quest Log remains available. |

On Forever, install and enable a QuestieDB build that supports public API
contract 4 and reports the Forever flavor through its status API or active
packaged-addon metadata. QuestieDB 1.1.1 packaged builds leave the status API's
expansion field empty, so QT checks their declared `X-Flavor` and `X-Mode`.
QuestTogether does not bundle the database. A missing, incompatible, incorrectly
configured or failing provider leaves the ordinary comparison usable and gives
a capability explanation. QT uses the provider's public composed reads,
including its applicable corrections.
See the [QuestieDB API contract](https://github.com/Questie/QuestieDB/blob/v1.1.1/docs/api.md).

Open Party Quest Log again or choose **Refresh** after a provider change. The
relationship index loads in scheduled batches; quest details load as needed.
Retail also updates from native quest-data events. Loading or missing information
is shown as such. This feature does not promise complete quest data for every
zone, character or client build.

## Preview a mixed party

Run `/qt pqlpreview chains` (also `/qt preview compare chains`) to open a
clearly labeled preview using a copy of your current quest log and the provider's
real relationships. Four simulated teammates demonstrate different steps,
readiness, completed history, missing quests and unknown progress. The preview
opens a related section automatically when one is available; the chain-link
buttons, grouping and objective expansion use the ordinary PQL layout.

Your own quest entries and local completion evidence remain real. The extra
players and their progress are simulated. Preview actions do not send messages,
share quests, alter your saved data or change your real focus, following or
waypoint. Refresh rebuilds the sample from your current log. Close the preview
or use `/qt pql` to return to ordinary comparison. The separate older
`/qt preview compare` mode retains its existing navigation-testing behavior.

The chain preview needs the same provider as ordinary PQL. It does not invent
relationships when data is unavailable. Empty logs remain empty; accept a quest
and Refresh to try its relationships.

## Reading the list

The **Filters** menu includes two saved preferences:

- **Group by chain** starts off. Turn it on to put matching active quests under
  their chain heading. Forever headings use **Related quests** with a known quest
  title; Retail uses the native line name when available. A group boundary and
  indented quest titles mark its members; unrelated quests return to the normal
  alignment outside that boundary.
- **Hide future quest names** starts on. Concealed titles stay hidden in rows,
  search, tooltips and actions. Current party quests, locally confirmed completed
  quests and names needed to explain a known prerequisite blocker can be shown.
  Turn this preference off to reveal future titles where data is available.

Search and filters still select the actual quests in the comparison. Added chain
context does not increase the quest, Missing, Ready or sharing counts. Group
headings explain when filters have hidden some active quests. Context needed to
understand prerequisites can remain visible beside a matching quest.

Each step uses the existing player columns. **In progress** and **Ready** describe
active quests; **Completed** requires character-specific completion evidence.
**Not in log** does not by itself mean completed or available. **Loading** and
**Unknown** retain that uncertainty. History from another character or account-wide
completion does not certify this character's progress, and repeatable quests are
not treated as permanently satisfied by an earlier completion.

Prerequisite explanations are separate from those log states. **Known
prerequisites met** means only the conditions QT can evaluate from available
evidence. Other availability conditions may still apply. Skill, reputation,
profession-rank, item, spell and specialization requirements are listed without
claiming they have been checked. Signed prerequisite IDs with undocumented
meaning remain unevaluated.

Branches retain their indentation and relationship information. Exclusions,
replacements, active-parent requirements, breadcrumbs and availability conditions
are distinct; they do not independently turn unrelated quests into one chain.
Missing references and cycles produce partial-information notices. Use **Show
earlier quests** and **Show later quests** to extend a large view. An exact
completed/total figure appears only for a verified complete linear path; branching
or partial data does not receive an invented percentage.

## Actions and quest-giver locations

Select a step to open its actions. Existing **Quest Details**, **Open in Quest
Log**, quest focus, following, **Share** and **Request Share** actions appear when
their usual conditions allow them. Viewing a chain or selecting a row does not
change your focused quest, follow target or waypoint.

For a revealed step in an expanded chain, each valid NPC or object starter
location has its own **Find quest giver** action, opening the map with a temporary
marker. Alternatives are offered with the current map first. Enable QT's
world-map markers with the QT button on the map to see this marker.
**Set waypoint** is a separate explicit action and uses
QT's existing waypoint and follow-confirmation behavior. An item-started quest
or unavailable location gets an explanation instead of a guessed destination.
Retail line membership alone does not supply quest-giver coordinates.

Mouse and keyboard navigation remain in the existing list. With supported native
gamepad navigation, move Up/Down between selectable rows and Left/Right between
controls. Select expands ordinary quest objectives, toggles a group, or opens a
step's actions. Back closes an action menu first, then the selected chain section
and returns to its origin; otherwise it closes Party Quest Log. See
[GAMEPAD.md](GAMEPAD.md) for setup and client limits.

## Data and validation boundaries

Chain context reuses QT's bounded character-history exchange. It does not add
synthetic quests to anyone's active log or broadcast a full completion history.
Closing or replacing the view retires its chain interests while ordinary party
sync continues. Diagnostics record bounded capability and count information,
not quest-title or player payload dumps.

Offline coverage exercises provider failures and loading, graph shapes and
partial data, history bounds, filters, spoiler concealment, row identity,
navigation and guarded actions. Live client rendering, physical controller
behavior, provider installation, map placement and multi-player behavior still
need separate acceptance. No live acceptance is claimed for this candidate.
