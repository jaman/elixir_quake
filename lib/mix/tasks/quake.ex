defmodule Mix.Tasks.Quake do
  @shortdoc "Play Quake in this terminal"

  @moduledoc """
  Play Quake in the terminal, from the shareware or registered game files or
  LibreQuake's.

      mix quake
      mix quake --dir /games/quake --map e1m1 --skill 2

  The first run opens a setup page (`Cauldron2D.Drafter.Launcher`). There you pick the
  game folder, the skill and how the game is drawn. Play saves your choices, and later
  runs start straight away with them. The page also opens when the saved folder no
  longer holds Quake's files, or when you pass `--launcher`. When nothing is saved yet,
  the folder is looked for in Steam's usual places first.

  Flags change one run without changing what is saved:

    * `--dir` — the game folder (holding `id1`, or `id1` itself); `QUAKE_DIR` or
      `config :elixir_quake, :dir` too
    * `--map` — the map to start on; default `start`, where you pick the episode and
      skill by walking
    * `--skill` — `0` (easy) to `3` (nightmare)
    * `--software`, `--gpu`, `--window` — draw without the graphics card, with it in the
      terminal, or with it in a window of its own whose keys play the game. Without
      these the saved drawing choice is used; its default draws on the graphics card
      when there is one.
    * `--picture` (or `CAULDRON_PICTURE`) — how pictures reach a terminal that keeps
      images, as `Cauldron2D.Drafter.Client.Picture` reads it; default `native:1,swap`
    * `--mute` — no sound (`CAULDRON_MUTE=1` too)
    * `--name` — the player name settings are kept under; default `ranger`
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture
  alias Cauldron2D.Drafter.Launcher

  @switches [
    dir: :string,
    map: :string,
    skill: :integer,
    name: :string,
    picture: :string,
    gpu: :boolean,
    window: :boolean,
    software: :boolean,
    launcher: :boolean,
    mute: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")
    name = Keyword.get(opts, :name, "ranger")

    overrides =
      %{
        dir: Keyword.get(opts, :dir) || Application.get_env(:elixir_quake, :dir),
        skill: opts[:skill]
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case Launcher.choose(ElixirQuake.Client, fields(),
           overrides: overrides,
           launcher: Keyword.get(opts, :launcher, false),
           player: name
         ) do
      {:ok, values} -> start(opts, name, values)
      :quit -> :ok
    end
  end

  defp fields do
    [
      %{
        key: :dir,
        label: "Quake folder",
        kind: {:path, &ElixirQuake.Assets.check/1},
        discover: &ElixirQuake.Assets.discover/0,
        hint: "the folder holding id1 (shareware, registered or LibreQuake)"
      },
      %{
        key: :skill,
        label: "Skill",
        kind: {:choice, [{0, "easy"}, {1, "normal"}, {2, "hard"}, {3, "nightmare"}]},
        default: 1
      },
      Launcher.drawing_field()
    ]
  end

  defp start(opts, name, values) do
    case ElixirQuake.Assets.load(values.dir) do
      {:ok, _assets} ->
        play(opts, name, values)

      {:error, reason} ->
        Mix.raise("could not read Quake files at #{values.dir}: #{inspect(reason)}")
    end
  end

  defp play(opts, name, values) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "30fps",
      props: %{
        game: ElixirQuake.Client,
        username: name,
        map: Keyword.get(opts, :map),
        skill: values.skill,
        picture: picture(opts),
        mute: opts[:mute]
      }
    )
  end

  defp picture(opts) do
    added = for switch <- [:gpu, :window, :software], Keyword.get(opts, switch, false), do: switch
    picture(Keyword.get(opts, :picture), added)
  end

  defp picture(nil, []), do: nil
  defp picture(nil, added), do: Map.fetch!(ElixirQuake.Client.look(), :picture) ++ added

  defp picture(options, added) do
    case Picture.parse(options) do
      {:ok, options} -> options ++ added
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end
end
