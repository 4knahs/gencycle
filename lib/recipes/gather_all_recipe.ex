defmodule GenCycle.Recipe.GatherAllRecipe do
  @moduledoc false

  require Logger

  @behaviour Patata.RecipeBehavior

  def start(state, event, message, {new_ev, new_status}) do

    running = Enum.filter(state.running_recipes, fn pid -> Process.alive?(pid) end)
    n_running = length running

    Logger.debug "GatherAllRecipe: There are #{n_running} running recipes!"

    time = DateTime.to_unix(DateTime.utc_now())
    events = Enum.filter(state.future_events,
      fn {_, _, unix_time} -> ( time < unix_time)  end)

    n_events = length events

    if n_events > 0 do
      # This can be ok in the case of the expire event for example but others should probably be canceled at this point.
      Logger.warn "GatherAllRecipe: There were #{n_events} scheduled events when WaitForAllRecipesRecipe was run."
    end

    case n_running do
      1 -> # Has to count with this recipe
        Logger.debug "GatherAllRecipe: All recipes were concluded launching: #{inspect {new_ev, new_status}}"
        {:event, new_ev, new_status}
      _ ->
        Logger.debug "GatherAllRecipe: Waiting for recipes to conclude (1s)"
        Process.sleep(1000)
        start(state, event, message, {new_ev, new_status})
    end
  end
end