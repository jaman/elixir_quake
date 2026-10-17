defmodule ElixirQuake.Assets do
  @moduledoc """
  The game's files, read once and shared by every process: the game directory, the
  palette and light table, the QuakeC program, and each map, model and sound the first
  time it is asked for.

      {:ok, _} = ElixirQuake.Assets.load("/games/quake")
      ElixirQuake.Assets.map("e1m1")
      ElixirQuake.Assets.model("progs/player.mdl")

  Everything is kept in `:persistent_term`; reading it copies nothing.
  """

  alias Cauldron2D.Drafter.Launcher
  alias Cauldron3D.Formats.{Bsp, Files, Mdl, Spr, Wad2, Wav}
  alias Cauldron3D.Texture
  alias TuningFork.{Sample, Voice}

  @key __MODULE__
  @hulls [
    {{-16.0, -16.0, -24.0}, {16.0, 16.0, 32.0}},
    {{-32.0, -32.0, -24.0}, {32.0, 32.0, 64.0}}
  ]

  @doc "`:ok` when `path` is a Quake game directory `load/1` can read, else `{:error, text}` for a person to read."
  @spec check(Path.t()) :: :ok | {:error, String.t()}
  def check(path) do
    with {:ok, files} <- Files.open(path, within: "id1"),
         palette when is_binary(palette) <- Files.read(files, "gfx/palette.lmp") do
      :ok
    else
      _other -> {:error, "no Quake files here (looking for id1 with pak0.pak)"}
    end
  end

  @doc "A Quake game directory in Steam's usual places that `check/1` accepts, or `nil`."
  @spec discover() :: Path.t() | nil
  def discover do
    "Quake"
    |> Launcher.steam_folders()
    |> Enum.flat_map(&[&1, Path.join(&1, "rerelease")])
    |> Enum.find(&(check(&1) == :ok))
  end

  @doc "Open the game directory at `path` (its `id1`, or the directory holding one) and read its palette and light table."
  @spec load(Path.t()) :: {:ok, map()} | {:error, term()}
  def load(path) do
    with {:ok, files} <- Files.open(path, within: "id1"),
         palette when is_binary(palette) <- Files.read(files, "gfx/palette.lmp"),
         colormap when is_binary(colormap) <- Files.read(files, "gfx/colormap.lmp") do
      assets = %{
        files: files,
        palette: binary_part(palette, 0, 768),
        colormap: binary_part(colormap, 0, 64 * 256),
        path: path
      }

      :persistent_term.put(@key, assets)
      {:ok, assets}
    else
      nil -> {:error, :missing_palette}
      error -> error
    end
  end

  @doc "Whether `load/1` has run."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(@key, nil) != nil

  @doc "What `load/1` read."
  @spec get() :: map()
  def get, do: :persistent_term.get(@key)

  @doc "The bytes of file `name`, or `nil`."
  @spec read(String.t()) :: binary() | nil
  def read(name), do: Files.read(get().files, name)

  @doc "The QuakeC program, `progs.dat`. Raises `ArgumentError` when there is none."
  @spec progs() :: QuakeC.Progs.t()
  def progs do
    cached(:progs, fn ->
      {:ok, progs} =
        QuakeC.Progs.parse(read("progs.dat") || raise(ArgumentError, "there is no progs.dat"))

      progs
    end)
  end

  @doc "The map `name` (without `maps/` or `.bsp`), as `%{bsp:, entities:}`, or `nil` when there is none."
  @spec map(String.t()) :: map() | nil
  def map(name), do: cached({:map, name}, fn -> parse_map("maps/#{name}.bsp") end)

  @doc """
  The model file `name`, as `%{kind:, data:, mins:, maxs:}`: `kind` `:alias` (a
  `Cauldron3D.Formats.Mdl`), `:sprite` (a `Cauldron3D.Formats.Spr`), `:brush` (a map
  file's world, as `%{bsp:, entities:}`) or `:missing`.
  """
  @spec model(String.t()) :: map()
  def model(name), do: cached({:model, name}, fn -> read_model(name) end)

  @doc "The sound `name` under `sound/` as a `TuningFork.Voice`, or `nil`."
  @spec sound(String.t()) :: Voice.t() | nil
  def sound(name), do: cached({:sound, name}, fn -> voice(read("sound/" <> name)) end)

  @doc "The `gfx.wad` pictures, by lower-case name; `conchars` is the 128 by 128 font."
  @spec pictures() :: %{String.t() => Texture.t()}
  def pictures,
    do:
      cached(:pictures, fn ->
        Wad2.pictures(read("gfx.wad"), raw: %{"conchars" => {128, 128}})
      end)

  @doc "A loose picture file such as `gfx/complete.lmp`, or `nil`."
  @spec picture(String.t()) :: Texture.t() | nil
  def picture(name), do: cached({:picture, name}, fn -> Wad2.lmp(read(name)) end)

  @doc """
  Quake's texture kinds by name: `sky…` is sky, split into a front layer (the left half,
  colour 0 see-through) and a back layer; `*…` is liquid; `trigger…` and `clip…` are
  hidden; everything else is solid.
  """
  @spec texture(String.t(), [Texture.t()]) :: map()
  def texture("sky" <> _ = name, [full | _] = mips) when full.width >= 2 do
    {front, back} = Texture.split(full, div(full.width, 2))
    %{name: name, kind: :sky, mips: mips, layers: [{front, 16.0}, {back, 8.0}]}
  end

  def texture("*" <> _ = name, mips), do: %{name: name, kind: :liquid, mips: mips}
  def texture("trigger" <> _ = name, mips), do: %{name: name, kind: :hidden, mips: mips}
  def texture("clip" <> _ = name, mips), do: %{name: name, kind: :hidden, mips: mips}
  def texture(name, mips), do: Bsp.solid(name, mips)

  defp cached(key, make) do
    case :persistent_term.get({@key, key}, :unread) do
      :unread ->
        value = make.()
        :persistent_term.put({@key, key}, value)
        value

      value ->
        value
    end
  end

  defp voice(data) do
    case Wav.read(data) do
      {:ok, %{rate: rate, pcm: pcm}} ->
        Voice.new(sample: Sample.from_pcm(pcm, rate: rate, root: 440.0), freq: 440.0, gain: 1.0)

      :error ->
        nil
    end
  end

  defp parse_bsp(data), do: Bsp.parse(data, hulls: @hulls, texture: &texture/2)

  defp parse_map(file) do
    with data when is_binary(data) <- read(file),
         {:ok, map} <- parse_bsp(data) do
      map
    else
      _ -> nil
    end
  end

  defp read_model(name) do
    data = read(name)

    cond do
      data == nil -> missing()
      String.ends_with?(name, ".mdl") -> from(Mdl.parse(data), :alias)
      String.ends_with?(name, ".spr") -> from(Spr.parse(data), :sprite)
      String.ends_with?(name, ".bsp") -> brush(parse_bsp(data))
      true -> missing()
    end
  end

  defp from({:ok, data}, kind), do: %{kind: kind, data: data, mins: data.mins, maxs: data.maxs}
  defp from(_error, _kind), do: missing()

  defp brush({:ok, %{bsp: bsp} = map}) do
    %{mins: mins, maxs: maxs} = elem(bsp.models, 0)
    %{kind: :brush, data: map, mins: mins, maxs: maxs}
  end

  defp brush(_error), do: missing()

  defp missing, do: %{kind: :missing, data: nil, mins: {0.0, 0.0, 0.0}, maxs: {0.0, 0.0, 0.0}}
end
