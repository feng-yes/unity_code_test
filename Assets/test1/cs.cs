using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class cs : MonoBehaviour
{
    public float dis = 10f;

    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
        Vector3 pos = ray.GetPoint(dis);
        transform.position = pos;
    }
}
