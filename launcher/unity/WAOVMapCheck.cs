// WAOVMapCheck.cs  (2026-11-14)  slider 3 UNITY CHECK. Editor only, runs in batch mode on a TEMP COPY of the avatar project.
// Called by map-unity-check.ps1:
//   Unity.exe -batchmode -nographics -quit -projectPath <temp copy> -executeMethod WAOVMapCheck.Run
//             -waovPackage <item .unitypackage> -waovPrefab <Assets/... item prefab> -waovRole <HumanBodyBones name>
//             -waovFallback <role or empty> -waovOffset "x,y,z" -waovOut <map-check.json>
// It never uploads, never signs in, never saves a scene, and only ever runs against the throwaway copy.
// Every case writes a row; "pass" is true only when every row is ok.
#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using UnityEditor;
using UnityEngine;

public static class WAOVMapCheck
{
    class Row { public string label, state, note; }
    static readonly List<Row> rows = new List<Row>();
    static void Add(string l, string s, string n) { rows.Add(new Row { label = l, state = s, note = n }); Debug.Log("[WAOV] " + s + " " + l + ": " + n); }

    static string Arg(string name)
    {
        var a = Environment.GetCommandLineArgs();
        for (int i = 0; i < a.Length - 1; i++) if (a[i] == name) return a[i + 1];
        return "";
    }

    public static void Run()
    {
        string outPath = Arg("-waovOut");
        try { Check(); }
        catch (Exception e) { Add("Unity check", "bad", "crashed: " + e.Message); }
        Write(outPath);
        EditorApplication.Exit(rows.Any(r => r.state == "bad") ? 2 : 0);
    }

    static void Check()
    {
        string pkg = Arg("-waovPackage"), prefabPath = Arg("-waovPrefab"), roleName = Arg("-waovRole"), fallback = Arg("-waovFallback");

        // 1 role name is a real HumanBodyBones value
        HumanBodyBones role;
        if (!Enum.TryParse(roleName, out role)) { Add("Body part", "bad", "unknown role " + roleName); return; }

        // 2 import the item package (synchronous in batch mode)
        if (!File.Exists(pkg)) { Add("Item package", "bad", "file not found"); return; }
        AssetDatabase.ImportPackage(pkg, false);
        AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
        Add("Item package", "ok", "imported " + Path.GetFileName(pkg));

        // 3 the item prefab exists and carries a Modular Avatar Bone Proxy
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(prefabPath);
        if (prefab == null) { Add("Item prefab", "bad", "not found at " + prefabPath); return; }
        var proxy = prefab.GetComponentsInChildren<Component>(true).FirstOrDefault(c => c != null && c.GetType().Name == "ModularAvatarBoneProxy");
        if (proxy == null) { Add("Bone Proxy", "bad", "the prefab has no MA Bone Proxy (is Modular Avatar installed?)"); return; }
        Add("Bone Proxy", "ok", "found on " + proxy.gameObject.name);

        // 4 find the avatar: a scene object, else the Humanoid model asset itself
        var avatar = FindAvatarRoot();
        if (avatar == null) { Add("Avatar", "bad", "no VRC Avatar Descriptor or Humanoid model found"); return; }
        var anim = avatar.GetComponentInChildren<Animator>(true);
        if (anim == null || anim.avatar == null || !anim.avatar.isHuman) { Add("Humanoid rig", "bad", "the avatar's Animator is not Humanoid"); return; }
        Add("Humanoid rig", "ok", avatar.name);

        // 5 the bone actually resolves on THIS avatar (the step that makes the map totally sure)
        var bone = anim.GetBoneTransform(role);
        if (bone == null && !string.IsNullOrEmpty(fallback))
        {
            HumanBodyBones fb;
            if (Enum.TryParse(fallback, out fb)) { bone = anim.GetBoneTransform(fb); if (bone != null) { Add("Body part", "warn", roleName + " not mapped, using " + fallback); role = fb; } }
        }
        if (bone == null) { Add("Body part", "bad", roleName + " is not mapped on this avatar"); return; }
        Add("Body part", "ok", roleName + " resolves to " + bone.name);

        // 6 place a copy, point the Bone Proxy at the role, and read back where it lands
        var inst = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
        inst.transform.SetParent(avatar.transform, false);
        var p = inst.GetComponentsInChildren<Component>(true).First(c => c != null && c.GetType().Name == "ModularAvatarBoneProxy");
        var so = new SerializedObject(p);
        var attach = so.FindProperty("boneReference");
        if (attach != null) { attach.intValue = (int)role; so.ApplyModifiedPropertiesWithoutUndo(); Add("Bone Proxy target", "ok", "set to " + role); }
        else Add("Bone Proxy target", "warn", "could not set boneReference (Modular Avatar version?), the prefab's own target is kept");

        // 7 sanity: the item is sized like a body part, not a building (scale check by renderer bounds vs avatar height)
        var rends = inst.GetComponentsInChildren<Renderer>(true);
        if (rends.Length == 0) Add("Item size", "warn", "no renderers to measure");
        else
        {
            var b = rends[0].bounds; foreach (var r in rends) b.Encapsulate(r.bounds);
            float height = Mathf.Max(0.1f, anim.GetBoneTransform(HumanBodyBones.Head).position.y - anim.GetBoneTransform(HumanBodyBones.Hips).position.y) * 2.2f;
            float ratio = b.size.magnitude / height;
            if (ratio > 1.5f) Add("Item size", "bad", "item is " + ratio.ToString("0.0") + "x the avatar height");
            else if (ratio < 0.005f) Add("Item size", "warn", "item looks tiny (" + ratio.ToString("0.000") + "x)");
            else Add("Item size", "ok", ratio.ToString("0.00") + "x the avatar height");
        }
        UnityEngine.Object.DestroyImmediate(inst);   // nothing is saved: the temp copy is thrown away anyway
    }

    static GameObject FindAvatarRoot()
    {
        foreach (var go in UnityEngine.Object.FindObjectsOfType<GameObject>())
            if (go.GetComponents<Component>().Any(c => c != null && c.GetType().Name == "VRCAvatarDescriptor")) return go;
        foreach (var guid in AssetDatabase.FindAssets("t:Model"))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            var imp = AssetImporter.GetAtPath(path) as ModelImporter;
            if (imp != null && imp.animationType == ModelImporterAnimationType.Human)
                return (GameObject)PrefabUtility.InstantiatePrefab(AssetDatabase.LoadAssetAtPath<GameObject>(path));
        }
        return null;
    }

    static string Esc(string s) { return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\""); }
    static void Write(string outPath)
    {
        var sb = new StringBuilder("{\"pass\":" + (rows.Any(r => r.state == "bad") ? "false" : "true") + ",\"rows\":[");
        sb.Append(string.Join(",", rows.Select(r => "{\"label\":\"" + Esc(r.label) + "\",\"state\":\"" + r.state + "\",\"note\":\"" + Esc(r.note) + "\"}")));
        sb.Append("]}");
        if (!string.IsNullOrEmpty(outPath)) File.WriteAllText(outPath, sb.ToString());
    }
}
#endif
