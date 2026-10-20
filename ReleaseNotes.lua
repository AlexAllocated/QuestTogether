-- Generated from release_notes.json by scripts/check_release_notes.py --write.
-- Edit the JSON source, then regenerate this file.
local QuestTogether = _G.QuestTogether

QuestTogether.releaseNotes = {
	version = "8.0.0",
	welcome = "Introducing QuestTogether VIP.",
	sections = {
		{
			title = "VIP cosmetics",
			items = {
				"VIP players have a class-colored star map marker, a gold-star QT chat prefix and minimap button, and a QuestTogether VIP label in their individual player tooltip. These rewards are cosmetic; they do not grant developer access.",
			},
			illustration = "vip-cosmetics",
		},
		{
			title = "Become a VIP",
			items = {
				"Share the QuestTogether download link with friends, your guild, a relevant Discord, or on social media. Screenshot your sent message or published post, showing the QT link and where you shared it. Send that screenshot in a Discord DM to @chevcast for review. Join the QT Discord server or send @chevcast a friend request first so your DM can get through. The VIP window includes the link to copy and the activation steps to follow after approval.",
			},
		},
		{
			title = "Activate your reward",
			items = {
				"Open the VIP window from the minimap menu, Settings, or /qt vip. Wait for @chevcast to confirm that VIP has been granted to your Discord account. The /qt claim command in Discord only works after that grant.\n\nThen copy your claim code with Ctrl+C and send it to @chevcast, or use /qt claim in the QT Discord server. Paste the private activation code you receive in the VIP window and choose Activate VIP. Repeat on Retail or Forever to use the same reward there.",
			},
		},
		{
			title = "Permanent and optional",
			items = {
				"Your reward is linked to your Discord account and shared across characters in each installation. Claim it separately on Retail and Forever. Turn off Show my VIP cosmetics to keep the reward without displaying it. Normal, VIP, and developer minimap buttons now have gold borders that follow the icon shape. Developer appearance takes priority over VIP.",
			},
		},
	},
}
