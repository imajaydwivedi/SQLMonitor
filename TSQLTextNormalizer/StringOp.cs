using CreatingWebAPIService.Models;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data.SqlTypes;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using TSQLTextNormalizer;

namespace TSQLTextNormalizer
{
    public class StringOp
    {
        [Microsoft.SqlServer.Server.SqlFunction(IsDeterministic = true)]
        public static SqlString sqlsig(SqlString input,SqlInt32 compatLevel,SqlBoolean caseSensitive)
        {
            String output = "";
           
            Parameter p = new Parameter();
            p.input = input.ToString();
            p.compatLevel = Int32.Parse(Convert.ToString(compatLevel));
            p.caseSensitive = Boolean.Parse(Convert.ToString(caseSensitive));

            output = new TSqlNormalizer().Normalize(p.input, p.compatLevel, p.caseSensitive);
            //Console.WriteLine(CallRestMethod(p));
            return output;
        }

        //public static string CallRestMethod(Parameter parameter)
        //{
        //    HttpWebRequest webrequest = (HttpWebRequest)WebRequest.Create("http://rm-uat.contoso.in/SQLDOMEPARSER/api/Home/getNormalize?input=" + parameter.input + "&compatLevel=" + parameter.compatLevel.ToString() + "&caseSensitive=" + parameter.caseSensitive.ToString());
        //    webrequest.Method = "GET";
        //    webrequest.ContentType = "application/x-www-form-urlencoded";

        //    HttpWebResponse webresponse = (HttpWebResponse)webrequest.GetResponse();
        //    Encoding enc = System.Text.Encoding.GetEncoding("utf-8");
        //    StreamReader responseStream = new StreamReader(webresponse.GetResponseStream(), enc);
        //    string result = string.Empty;
        //    result = responseStream.ReadToEnd();
        //    webresponse.Close();
        //    return result;
        //}
    }
}
