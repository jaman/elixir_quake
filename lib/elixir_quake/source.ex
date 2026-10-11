defmodule ElixirQuake.Source do
  @moduledoc "Quake's program, maps and models for `QuakeServer`, from `ElixirQuake.Assets`."

  @behaviour QuakeServer.Source

  alias ElixirQuake.Assets

  @impl true
  def progs, do: Assets.progs()

  @impl true
  def map(name), do: Assets.map(name)

  @impl true
  def model(name), do: Assets.model(name)
end
