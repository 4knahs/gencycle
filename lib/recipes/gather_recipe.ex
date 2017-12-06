defmodule GenCycle.Recipe.GatherRecipe do
  @moduledoc false

  require Logger
  alias Gencycle

  @behaviour Patata.RecipeBehavior

  def start(state, event, message,
        [{:in_event, event_start}, {:out, {new_ev, new_message}}, {:events, events}]) do

    gather(state, {event, message}, event_start, new_ev, new_message, events)
  end

  def gather(state, {event, message}, event_start, new_ev, new_message, events) do

    reverse_history = Enum.reverse(state.history)

    cond do
      # All events matched
      match_events(event_start, events, reverse_history) ->
        Logger.info "GatherRecipe: Matched all the events for gather recipe: #{inspect events}. Launching #{inspect {new_ev, new_message}}"
        {:event, new_ev, new_message}
      true ->
        :no_event
    end
  end

  defp match_events(last_event, events, history, matched_last \\ false)
  defp match_events(last_event, [], history, true) do
    true # We matched all the events
  end
  defp match_events(last_event, events, history, true) do
    Logger.debug "GatherRecipe: Found #{inspect last_event} and could not match #{inspect events}"
    false # Matched last and still had events
  end
  defp match_events(last_event, events, [], false) do
    Logger.debug "GatherRecipe: Couldnt find #{inspect last_event}!"
    false # Either there was no history or we didnt find the last_event
  end
  defp match_events(last_event, events, history, matched_last) do
    current_event = hd(history)

    cond do
      current_event == last_event ->
        Logger.debug "GatherRecipe: Matched last event : #{inspect last_event}"
        match_events(last_event, events, tl(history), true) # There are still events and we matched the last_event
      true ->
        match_events(last_event,
          events -- [current_event], # Remove matched event
          tl(history),
          matched_last) # Advance to the next event in history
    end
  end
end
