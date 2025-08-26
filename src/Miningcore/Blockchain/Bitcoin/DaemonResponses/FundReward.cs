using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Miningcore.Blockchain.Bitcoin.DaemonResponses
{
    public class FundReward
    {
        public string Payee { get; set; }
        public string Script { get; set; }
        public long Amount { get; set; }
    }

    public class FundRewardBlockTemplateExtra
    {
        public JToken FundReward { get; set; }

        [JsonProperty("fundreward_payments_started")]
        public bool FundRewardPaymentsStarted { get; set; }
    }
}
