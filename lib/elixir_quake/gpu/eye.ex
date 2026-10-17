defmodule ElixirQuake.Gpu.Eye do
  @moduledoc """
  The view's eye as a `CauldronGPU.Camera`: at the view camera's origin, turned by its
  pitch, yaw and roll, drawing into the part of the picture `ElixirQuake.Screen` gives
  the world view, with Quake's vertical field of view (that of 90 degrees across a 4:3
  picture) over that part's height and its width as wide as it shows on screen.

      ElixirQuake.Gpu.Eye.camera(view.camera, layout, scale, snap?)
  """

  alias CauldronGPU.{Camera, Quat}
  alias ElixirQuake.Screen

  @quake_tangent 0.75
  @near 1.0
  @far 8192.0

  @doc """
  The camera for `eye` (`%{origin:, angles:}`, angles `{pitch, yaw, roll}` in degrees,
  pitch above zero looking down) in a picture laid out as `layout`, map units `scale`
  metres each; `snap?` places it without moving from where it was.
  """
  @spec camera(map(), Screen.t(), number(), boolean()) :: Camera.t()
  def camera(%{origin: {x, y, z}, angles: {pitch, yaw, roll}}, %Screen{} = layout, scale, snap?) do
    {view_width, view_height} = layout.view
    {left, top} = layout.at

    %Camera{
      position: {x * scale, z * scale, -y * scale},
      rotation: rotation(pitch, yaw, roll),
      fov_y: 2 * :math.atan(@quake_tangent),
      near: @near * scale,
      far: @far * scale,
      snap: snap?,
      viewport:
        {left / layout.width, top / layout.height, view_width / layout.width,
         view_height / layout.height},
      aspect: view_width * layout.aspect / view_height
    }
  end

  defp rotation(pitch, yaw, roll) do
    (yaw - 90)
    |> radians()
    |> Quat.yaw_pitch(-radians(pitch))
    |> Quat.multiply(Quat.axis_angle({0, 0, 1}, -radians(roll)))
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
