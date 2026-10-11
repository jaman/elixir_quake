defmodule Mix.Tasks.Quake do
  @shortdoc "Play Quake in this terminal"

  @moduledoc """
  Play Quake in the terminal, from the shareware or registered game files or
  LibreQuake's.

      mix quake --dir /games/quake
      mix quake --dir /games/quake --map e1m1 --skill 2

  `--dir` is the game directory (holding `pak0.pak`) or the one above it holding
  `id1`; it defaults to `config :elixir_quake, :dir`, which `QUAKE_DIR` sets.
  `--map` defaults to `start`, where the episode and skill are chosen by walking.
  `--skill` is `0` (easy) to `3` (nightmare), default `1`. `--picture` (or `CAULDRON_PICTURE`) is how the picture
  reaches a terminal that keeps images, as `Cauldron2D.Drafter.Client.Picture` reads it:
  any of `native`, `native:N`, `size:WxH`, `png` and `swap`, comma separated, or
  `none`; default `native:1,swap`. `--mute` plays no sound
  (`CAULDRON_MUTE=1` too).
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture

  @switches [
    dir: :string,
    map: :string,
    skill: :integer,
    name: :string,
    picture: :string,
    mute: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")
    dir = Keyword.get(opts, :dir) || Application.get_env(:elixir_quake, :dir)

    case dir && ElixirQuake.Assets.load(dir) do
      {:ok, _assets} -> play(opts)
      {:error, reason} -> Mix.raise("could not read Quake files at #{dir}: #{inspect(reason)}")
      nil -> Mix.raise("give the game directory: mix quake --dir path/to/quake")
    end
  end

  defp play(opts) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "30fps",
      props: %{
        game: ElixirQuake.Client,
        username: Keyword.get(opts, :name, "ranger"),
        map: Keyword.get(opts, :map),
        skill: Keyword.get(opts, :skill, 1),
        picture: picture(opts[:picture]),
        mute: opts[:mute]
      }
    )
  end

  defp picture(nil), do: nil

  defp picture(options) do
    case Picture.parse(options) do
      {:ok, options} -> options
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end
end
