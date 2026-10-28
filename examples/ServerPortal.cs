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
[Cilboxable]
public class ServerPortal : MonoBehaviour
{
    public string host = "worlds.example.com";
    public int port = 4296;
    public string destination = "To the Hub";
    public BasisInteractableButton door;
    public TextMeshPro labelFront;
    public TextMeshPro labelBack;

    void Start()
    {
        door.ButtonDown = OnPressed;
        Show(destination);
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
    }

    void Show(string text)
    {
        labelFront.text = text;
        labelBack.text = text;
    }
}
