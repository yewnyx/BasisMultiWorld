using Basis.Scripts.BasisSdk.Interactions;
using Basis.Shims;
using Cilbox;
using TMPro;
using UnityEngine;

// A press-to-travel door for a Basis prop. Pressing it asks the player's client to move to host:port;
// the client shows the address and the player confirms. Pass the bare host name with port 4296 so
// the client looks the world up by SRV: DNS then decides which server and port the door leads to.
//
// Inside a prop (CilboxPropBasis) the creator guide's ServerPortal example fails. This version follows
// the prop rules, as tested by Splat Basis:
// - assign ButtonDown (props may only set it, so "+=" fails);
// - use BasisInteractableButton (BasisInteractableShim isn't allowed in props);
// - pass the result callback as a method group on this class, not a lambda;
// - put a CilboxPropBasis on the prop's own root object, or the script never ships.
//
// After a Cancel or a failed hop the sign shows a message for a few seconds, then the destination
// again. The component is switched on only for that time, so no Update runs while the door is idle.
// Props forward Update and allow Time and enabled, but run no coroutines or Invoke.
[Cilboxable]
public class ServerPortal : MonoBehaviour
{
    const float RestoreSeconds = 3f;

    public string host = "worlds.example.com";
    public int port = 4296;
    public string destination = "To the Hub";
    public BasisInteractableButton door;
    public TextMeshPro labelFront;
    public TextMeshPro labelBack;
    float restoreAt;   // when the message gives way to the destination again

    void Start()
    {
        door.ButtonDown = OnPressed;
        Show(destination);
        enabled = false;
    }

    void Update()
    {
        if (Time.time < restoreAt) return;
        Show(destination);
        enabled = false;
    }

    void OnPressed()
    {
        Show(destination);
        BasisConnectionShim.RequestConnect(this, host, (ushort)port, null, OnResult);
    }

    void OnResult(BasisConnectionResult result)
    {
        if (result == BasisConnectionResult.Accepted) return;
        Show(result == BasisConnectionResult.Declined ? "Maybe next time" : "Can't travel now");
        restoreAt = Time.time + RestoreSeconds;
        enabled = true;
    }

    void Show(string text)
    {
        labelFront.text = text;
        labelBack.text = text;
    }
}
