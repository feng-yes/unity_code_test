using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class c_sdf : MonoBehaviour
{
	public Material material = null;

    // Start is called before the first frame update
    void Start()
    {
		if (material == null) {
			Renderer renderer = gameObject.GetComponent<Renderer>();
			if (renderer == null) {
				Debug.LogWarning("Cannot find a renderer.");
				return;
			}

			material = renderer.sharedMaterial;
        }
        material.SetFloat("_xScale", transform.localScale.x);
        material.SetFloat("_yScale", transform.localScale.y);
    }

    void Update()
    {
		// if (material == null) {
		// 	Renderer renderer = gameObject.GetComponent<Renderer>();
		// 	if (renderer == null) {
		// 		Debug.LogWarning("Cannot find a renderer.");
		// 		return;
		// 	}

		// 	material = renderer.sharedMaterial;
        // }
        // material.SetFloat("_xScale", transform.localScale.x);
        // material.SetFloat("_yScale", transform.localScale.y);
    }
}
