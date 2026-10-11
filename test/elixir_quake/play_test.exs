defmodule ElixirQuake.PlayTest do
  use ExUnit.Case, async: false

  alias ElixirQuake.{Assets, Game}
  alias QuakeServer.Edicts

  @dir System.get_env("QUAKE_DIR")
  @moduletag skip:
               if(@dir,
                 do: false,
                 else: "set QUAKE_DIR to a Quake or LibreQuake directory to play a level"
               )

  setup_all do
    {:ok, _} = Assets.load(@dir)
    :ok
  end

  defp play(state, held, frames) do
    state = Game.handle_input(state, :player, %{held: MapSet.new(held)})
    Enum.reduce(1..frames, state, fn _, acc -> Game.step(acc, 1 / 60) end)
  end

  test "the player walks where they face, and one press of fire spends one shell" do
    state = Game.init(map: Enum.find(["e1m1", "lq_e1m1"], &Assets.map/1), skill: 1)
    {:ok, state} = Game.join(state, :player, %{})
    {sx, sy, _} = Edicts.vector(state.server, 1, "origin")
    {_, yaw, _} = state.angles

    state = play(state, [:forward], 60)
    {x, y, _} = Edicts.vector(state.server, 1, "origin")
    radians = yaw * :math.pi() / 180
    along = (x - sx) * :math.cos(radians) + (y - sy) * :math.sin(radians)
    assert along > 150

    shells = Edicts.float(state.server, 1, "ammo_shells")
    state = state |> play([:fire], 2) |> play([], 60)
    assert Edicts.float(state.server, 1, "ammo_shells") == shells - 1
  end
end
