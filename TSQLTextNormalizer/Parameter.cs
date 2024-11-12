using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace CreatingWebAPIService.Models
{
    public class Parameter
    {
        public String input { get; set; }
        public int compatLevel { get; set; }
        public bool caseSensitive { get; set; }
    }
}