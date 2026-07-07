# Roll Lottery Archive

Archived at: 2026-06-30

## Scope

The legacy `RollPage` lottery has been archived and hidden.

Archived code/data:

- `src/shared/RollConfig.luau`
- `src/client/UI/RollController.luau`
- `ReplicatedStorage.PerformRollRF` server handling in `src/server/PlayerDataManager.luau`
- Legacy online timer that granted `RollTickets[1]`
- Legacy player data field `RollTickets`

## Current Behavior

- `RollConfig.Enabled` is `false`.
- `RollController.Init()` no longer binds or opens the old Roll page.
- If `BasicGui.PlayProperty.Roll` still exists, the client hides and disables it.
- If `BasicGui.RollPage` still exists, the client hides/disables it.
- The old 5-minute online timer no longer grants legacy `RollTickets`.
- If an old client invokes `PerformRollRF`, the server returns the disabled message and does not spend currency, consume tickets, or grant rewards.

## Historical Pools

The old pools in `RollConfig.Pools` are intentionally kept as historical records only. They should not be used for live gameplay while `RollConfig.Enabled == false`.

## Not Affected

The newer IAP shop exclusive lottery is not part of this archive and remains active:

- `src/shared/ExclusiveRollConfig.luau`
- `src/client/UI/IAPShopController.luau`
- `src/server/Services/IAPService.luau`
- `IAPShopGui/Store/StoreFrame/Container/Exclusive`
- `IAPShopGui/Store/StoreFrame/Container/Exclusive1`
- `IAPShopGui/Store/StoreFrame/Container/Exclusive2`

## Studio Cleanup

It is safe to delete the old `RollPage` UI after this archive change. If the old entry button remains at `BasicGui/PlayProperty/Roll`, the client will hide it automatically, but deleting it is also safe.
