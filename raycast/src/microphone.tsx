import { Action, ActionPanel, Color, Icon, List, showToast, Toast } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { AudioDevice, readDevices, readPriority, writePriority } from "./utt";

/**
 * The priority list, plus every input utt can currently see.
 *
 * utt records from the first device on the list that is actually plugged in, so
 * the useful thing to show is the order — not a single checked radio button.
 */
export default function Command() {
  const { data, isLoading, revalidate } = usePromise(async () => {
    const [devices, priority] = await Promise.all([readDevices(), readPriority()]);
    return { devices, priority };
  });

  const devices = data?.devices ?? [];
  const priority = data?.priority ?? [];
  const nameOf = (uid: string) => devices.find((device) => device.id === uid)?.name ?? uid;
  const isConnected = (uid: string) => devices.some((device) => device.id === uid);
  const unlisted = devices.filter((device) => !priority.includes(device.id));

  async function apply(next: string[], message: string) {
    await writePriority(next);
    revalidate();
    await showToast({ style: Toast.Style.Success, title: message });
  }

  const useSystemDefault = (
    <Action
      title="Use System Default"
      icon={Icon.Undo}
      shortcut={{ modifiers: ["cmd"], key: "0" }}
      onAction={() => apply([], "Following the system default input")}
    />
  );

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter microphones…">
      <List.EmptyView
        icon={Icon.Microphone}
        title="No microphones found"
        description="utt exports the list while it is running. Launch utt once, then come back."
      />

      <List.Section title="Priority" subtitle={priority.length ? "first one that is plugged in wins" : undefined}>
        {priority.map((uid, index) => (
          <List.Item
            key={uid}
            icon={index === 0 ? { source: Icon.Microphone, tintColor: Color.Green } : Icon.Microphone}
            title={nameOf(uid)}
            subtitle={`${index + 1}`}
            accessories={isConnected(uid) ? [] : [{ tag: { value: "not connected", color: Color.Orange } }]}
            actions={
              <ActionPanel>
                <Action
                  title="Move to Top"
                  icon={Icon.ArrowUpCircle}
                  onAction={() => apply([uid, ...priority.filter((id) => id !== uid)], `Recording from ${nameOf(uid)}`)}
                />
                <Action
                  title="Move Up"
                  icon={Icon.ArrowUp}
                  shortcut={{ modifiers: ["cmd", "shift"], key: "arrowUp" }}
                  onAction={() => apply(swapped(priority, index, index - 1), "Priority updated")}
                />
                <Action
                  title="Move Down"
                  icon={Icon.ArrowDown}
                  shortcut={{ modifiers: ["cmd", "shift"], key: "arrowDown" }}
                  onAction={() => apply(swapped(priority, index, index + 1), "Priority updated")}
                />
                <Action
                  title="Remove from Priority"
                  icon={Icon.Trash}
                  style={Action.Style.Destructive}
                  shortcut={{ modifiers: ["ctrl"], key: "x" }}
                  onAction={() => apply(priority.filter((id) => id !== uid), `Removed ${nameOf(uid)}`)}
                />
                {useSystemDefault}
              </ActionPanel>
            }
          />
        ))}
      </List.Section>

      <List.Section title={priority.length ? "Other inputs" : "Inputs"}>
        {unlisted.map((device: AudioDevice) => (
          <List.Item
            key={device.id}
            icon={Icon.Microphone}
            title={device.name}
            actions={
              <ActionPanel>
                <Action
                  title="Use This Microphone"
                  icon={Icon.Check}
                  onAction={() => apply([device.id, ...priority], `Recording from ${device.name}`)}
                />
                <Action
                  title="Add as Fallback"
                  icon={Icon.Plus}
                  onAction={() => apply([...priority, device.id], `${device.name} added as a fallback`)}
                />
                {useSystemDefault}
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}

/** Out-of-range index means the row is already at an end; nothing moves. */
function swapped(list: string[], from: number, to: number): string[] {
  if (to < 0 || to >= list.length) return list;
  const next = [...list];
  [next[from], next[to]] = [next[to], next[from]];
  return next;
}
